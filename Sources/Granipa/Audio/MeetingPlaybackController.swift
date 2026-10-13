import AVFoundation
import Foundation
import Observation

enum MeetingPlaybackError: Equatable, Sendable {
    case missingFile
    case loadFailed(String)
}

/// Players started with play(atTime:) report isPlaying == false until the
/// scheduled time; that window is playing, not end-of-file.
enum PlaybackClock {
    static let startGrace: TimeInterval = 0.25

    static func isPlaying(
        leadIsPlaying: Bool, intendsToPlay: Bool, deviceTime: TimeInterval,
        scheduledStart: TimeInterval
    ) -> Bool {
        leadIsPlaying || (intendsToPlay && deviceTime < scheduledStart + startGrace)
    }
}

/// What the meeting player plays: both recordings together (what was heard
/// in the room), or one channel alone.
enum PlaybackSource: String, CaseIterable, Sendable {
    case both, mic, system

    var title: String {
        switch self {
        case .both: "Both"
        case .mic: "Mic"
        case .system: "System"
        }
    }
}

enum MeetingPlaybackState: Equatable, Sendable {
    case idle
    /// A file is being opened and prepared off the main actor.
    case preparing
    case ready
    case playing
    case paused
    case ended
    case failed(MeetingPlaybackError)
}

/// Sole owner of the AVAudioPlayers. Opening and preparing a meeting-length
/// recording does real I/O (measured ~150 ms on a one-hour AAC, unbounded on
/// slow disks); owning the players here keeps that work off the main actor
/// without any Sendable escape hatch. Calls serialize, so effects issued in
/// order (seek, then play) apply in order.
private actor PlaybackEngine {
    /// Longest recording first: it drives the clock and the end of playback.
    private var players: [AVAudioPlayer] = []
    /// Intent, not AVAudioPlayer.isPlaying: during the sync lead the players
    /// are scheduled but report not playing yet.
    private var running = false
    /// Output-device time the current start was scheduled for.
    private var scheduledStart: TimeInterval = 0
    /// Players started together share one output-device start time, so the
    /// mic and system tracks stay aligned like the meeting itself.
    private static let syncLead: TimeInterval = 0.05

    /// Tears down any previous players, then opens and prepares the new ones.
    func replace(
        urls: [URL], rate: Float, delegate: PlaybackDelegateBox?,
        secondaryDelegate: PlaybackDelegateBox?
    ) throws -> TimeInterval {
        reset()
        var opened: [AVAudioPlayer] = []
        for url in urls {
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.enableRate = true
            audio.rate = rate
            audio.prepareToPlay()
            opened.append(audio)
        }
        opened.sort { $0.duration > $1.duration }
        for (index, player) in opened.enumerated() {
            player.delegate = index == 0 ? delegate : secondaryDelegate
        }
        players = opened
        return opened.first?.duration ?? 0
    }

    func play(rate: Float) -> Bool {
        guard let lead = players.first else { return false }
        if players.count == 1 {
            lead.rate = rate
            scheduledStart = lead.deviceCurrentTime
            running = lead.play()
            return running
        }
        // A shorter track that already ended reports currentTime 0, so every
        // track is placed at the lead's time; tracks past their end stay quiet.
        let position = lead.currentTime
        let start = lead.deviceCurrentTime + Self.syncLead
        scheduledStart = start
        var started = true
        for player in players {
            player.rate = rate
            guard position < player.duration else { continue }
            player.currentTime = position
            started = player.play(atTime: start) && started
        }
        // A half-started pair would play one track behind a failed facade.
        if !started { players.forEach { $0.pause() } }
        running = started
        return started
    }

    func pause() {
        players.forEach { $0.pause() }
        running = false
    }

    func seek(to time: TimeInterval) {
        let wasPlaying = running
        let rate = players.first?.rate ?? 1
        if wasPlaying, players.count > 1 { pause() }
        for player in players {
            player.currentTime = min(time, player.duration)
        }
        if wasPlaying, players.count > 1 { _ = play(rate: rate) }
    }

    func setRate(_ rate: Float) {
        players.forEach { $0.rate = rate }
    }

    func currentTime() -> TimeInterval {
        players.first?.currentTime ?? 0
    }

    func duration() -> TimeInterval {
        players.first?.duration ?? 0
    }

    func isPlaying() -> Bool {
        guard let lead = players.first else { return false }
        let playing = PlaybackClock.isPlaying(
            leadIsPlaying: lead.isPlaying, intendsToPlay: running,
            deviceTime: lead.deviceCurrentTime, scheduledStart: scheduledStart)
        if !playing { running = false }
        return playing
    }

    /// The lead track finished on its own.
    func endReached() {
        running = false
    }

    func stopPlayback() {
        players.forEach { $0.stop() }
        running = false
    }

    func playingTrackCount() -> Int {
        players.filter(\.isPlaying).count
    }

    func reset() {
        for player in players {
            player.stop()
            player.delegate = nil
        }
        players = []
        running = false
    }
}

@MainActor
@Observable
final class MeetingPlaybackController {
    static let rates: [Float] = [1, 1.5, 2]

    private(set) var state: MeetingPlaybackState = .idle
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var rate: Float = 1
    private(set) var source: PlaybackSource = .both
    private(set) var availableSources: [PlaybackSource] = []
    private(set) var loadedURLs: [URL] = []

    var isPlaying: Bool { state == .playing }

    @ObservationIgnored private let engine = PlaybackEngine()
    @ObservationIgnored private var delegateBox: PlaybackDelegateBox?
    @ObservationIgnored private var secondaryDelegateBox: PlaybackDelegateBox?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    /// Serializes engine effects so ordered calls (seek then play) and a
    /// channel replacement apply in submission order.
    @ObservationIgnored private var controlTask: Task<Void, Never> = Task {}
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var micPath: String?
    @ObservationIgnored private var systemPath: String?

    func load(micPath: String?, systemPath: String?, preferred: PlaybackSource? = nil) {
        cancelOpen()
        currentTime = 0
        duration = 0
        loadedURLs = []
        self.micPath = micPath
        self.systemPath = systemPath
        availableSources = Self.sources(micPath: micPath, systemPath: systemPath)
        guard let first = availableSources.first else {
            state = .idle
            releaseEngine()
            return
        }
        if let preferred, availableSources.contains(preferred) {
            source = preferred
        } else {
            source = first
        }
        openCurrentSource(resumingAt: nil)
    }

    func play() {
        switch state {
        case .ready, .paused, .playing:
            break
        case .ended:
            currentTime = 0
        case .idle, .preparing, .failed:
            return
        }
        let restartsFromStart = state == .ended
        let appliedRate = rate
        let current = generation
        state = .playing
        enqueue { engine in
            if restartsFromStart {
                await engine.seek(to: 0)
            }
            let started = await engine.play(rate: appliedRate)
            // The button already showed .playing; ticking may only start
            // once the engine is actually playing for this generation and
            // the intent is still to play. Earlier, a tick's first
            // isPlaying read could run before engine.play and read as EOF.
            guard started, current == self.generation, self.state == .playing else {
                if started {
                    await engine.pause()
                } else if self.state == .playing {
                    self.state = .failed(.loadFailed("Could not start playback"))
                }
                return
            }
            self.startTick()
        }
    }

    func pause() {
        guard state == .playing else { return }
        state = .paused
        tickTask?.cancel()
        tickTask = nil
        // Keep the last tick's time: it is what the user saw when pressing
        // pause, and reading the engine clock back would race the tick's
        // own staleness. The next play or seek resyncs.
        enqueue { engine in
            await engine.pause()
        }
    }

    func togglePlaying() {
        if isPlaying { pause() } else { play() }
    }

    func seek(to time: TimeInterval) {
        guard duration > 0 else {
            currentTime = 0
            return
        }
        let clamped = min(max(0, time), duration)
        currentTime = clamped
        if state == .ended, clamped < duration {
            state = .paused
        }
        enqueue { engine in
            await engine.seek(to: clamped)
        }
    }

    func setRate(_ rate: Float) {
        guard Self.rates.contains(rate) else { return }
        self.rate = rate
        enqueue { engine in
            await engine.setRate(rate)
        }
    }

    func selectSource(_ source: PlaybackSource) {
        guard source != self.source, availableSources.contains(source) else { return }
        let resumeTime = currentTime
        self.source = source
        openCurrentSource(resumingAt: duration > 0 ? min(resumeTime, duration) : nil)
    }

#if DEBUG
    func playingTrackCountForTesting() async -> Int {
        await controlTask.value
        return await engine.playingTrackCount()
    }
#endif

    func stopAndRelease() {
        cancelOpen()
        micPath = nil
        systemPath = nil
        availableSources = []
        state = .idle
        releaseEngine()
    }

    // MARK: - Preparation

    private func openCurrentSource(resumingAt resume: TimeInterval?) {
        let paths: [String?]
        switch source {
        case .both: paths = [micPath, systemPath]
        case .mic: paths = [micPath]
        case .system: paths = [systemPath]
        }
        let present = paths.compactMap { $0 }
        guard present.count == paths.count, !present.isEmpty else {
            state = .idle
            releaseEngine()
            return
        }
        for path in present {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                !isDirectory.boolValue
            else {
                state = .failed(.missingFile)
                releaseEngine()
                return
            }
        }
        // Also covers selectSource: anything that abandons the current
        // players must stop its tick before preparing the replacement.
        cancelOpen()
        let current = generation
        let urls = present.map { URL(fileURLWithPath: $0) }
        state = .preparing
        delegateBox?.controller = nil
        secondaryDelegateBox?.controller = nil
        let box = PlaybackDelegateBox()
        box.controller = self
        delegateBox = box
        let secondaryBox = PlaybackDelegateBox(drivesEnd: false)
        secondaryBox.controller = self
        secondaryDelegateBox = secondaryBox
        let appliedRate = rate
        enqueue { engine in
            do {
                let preparedDuration = try await engine.replace(
                    urls: urls, rate: appliedRate, delegate: box,
                    secondaryDelegate: secondaryBox)
                guard current == self.generation else { return }
                self.loadedURLs = urls
                self.duration = preparedDuration
                self.currentTime = 0
                self.state = .ready
                if let resume {
                    let position = min(resume, preparedDuration)
                    self.currentTime = position
                    await engine.seek(to: position)
                }
            } catch {
                guard current == self.generation else { return }
                self.state = .failed(.loadFailed(error.localizedDescription))
            }
        }
    }

    /// Runs `operation` after every previously issued one. State reads and
    /// writes stay on the main actor; only engine effects hop.
    private func enqueue(_ operation: @escaping @MainActor (PlaybackEngine) async -> Void) {
        controlTask = Task { @MainActor [previous = controlTask] in
            await previous.value
            await operation(engine)
        }
    }

    /// Abandons the current player on every path that will not replace it:
    /// detaches the delegate and clears the loaded-file facade on the main
    /// actor, then stops and releases the engine's player through the
    /// command chain. Without this, loading nil/nil or a missing path left a
    /// playing file audible under an idle/failed facade.
    private func releaseEngine() {
        delegateBox?.controller = nil
        delegateBox = nil
        secondaryDelegateBox?.controller = nil
        secondaryDelegateBox = nil
        loadedURLs = []
        duration = 0
        currentTime = 0
        enqueue { engine in
            await engine.reset()
        }
    }

    private func cancelOpen() {
        generation += 1
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - End of playback

    fileprivate func handleFinished(successfully: Bool) {
        tickTask?.cancel()
        tickTask = nil
        enqueue { engine in
            await engine.endReached()
        }
        if successfully {
            currentTime = duration
            state = .ended
        } else {
            state = .paused
            enqueue { engine in
                self.currentTime = await engine.currentTime()
            }
        }
    }

    fileprivate func handleDecodeError(_ message: String) {
        tickTask?.cancel()
        tickTask = nil
        state = .failed(.loadFailed(message))
        enqueue { engine in
            await engine.stopPlayback()
        }
    }

    private func startTick() {
        tickTask?.cancel()
        let current = generation
        tickTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, current == self.generation,
                self.state == .playing
            {
                let time = await self.engine.currentTime()
                let playerDuration = await self.engine.duration()
                let stillPlaying = await self.engine.isPlaying()
                // The awaits free the main actor: a load, stop or pause can
                // have advanced the state in between, so nothing may be
                // published — and EOF declared — without re-validating.
                guard !Task.isCancelled, current == self.generation,
                    self.state == .playing
                else { break }
                self.currentTime = time
                if playerDuration > 0 {
                    self.duration = playerDuration
                }
                if !stillPlaying {
                    self.handleFinished(successfully: true)
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private static func sources(micPath: String?, systemPath: String?) -> [PlaybackSource] {
        switch (micPath != nil, systemPath != nil) {
        case (true, true): [.both, .mic, .system]
        case (true, false): [.mic]
        case (false, true): [.system]
        case (false, false): []
        }
    }
}

/// AVAudioPlayer callbacks can arrive off the main actor; hop back in.
private final class PlaybackDelegateBox: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    weak var controller: MeetingPlaybackController?
    /// Only the longest track's finish ends playback; any track's decode
    /// error is reported.
    private let drivesEnd: Bool

    init(drivesEnd: Bool = true) {
        self.drivesEnd = drivesEnd
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard drivesEnd else { return }
        Task { @MainActor in
            controller?.handleFinished(successfully: flag)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error?.localizedDescription ?? "Decode failed"
        Task { @MainActor in
            controller?.handleDecodeError(message)
        }
    }
}
