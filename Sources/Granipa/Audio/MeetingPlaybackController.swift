import AVFoundation
import Foundation
import Observation

enum MeetingPlaybackError: Equatable, Sendable {
    case missingFile
    case loadFailed(String)
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

/// Sole owner of the AVAudioPlayer. Opening and preparing a meeting-length
/// recording does real I/O (measured ~150 ms on a one-hour AAC, unbounded on
/// slow disks); owning the player here keeps that work off the main actor
/// without any Sendable escape hatch. Calls serialize, so effects issued in
/// order (seek, then play) apply in order.
private actor PlaybackEngine {
    private var player: AVAudioPlayer?

    /// Tears down any previous player, then opens and prepares the new one.
    func replace(url: URL, rate: Float, delegate: PlaybackDelegateBox?) throws -> TimeInterval {
        reset()
        let audio = try AVAudioPlayer(contentsOf: url)
        audio.enableRate = true
        audio.rate = rate
        audio.delegate = delegate
        audio.prepareToPlay()
        player = audio
        return audio.duration
    }

    func play(rate: Float) -> Bool {
        guard let player else { return false }
        player.rate = rate
        return player.play()
    }

    func pause() {
        player?.pause()
    }

    func seek(to time: TimeInterval) {
        player?.currentTime = time
    }

    func setRate(_ rate: Float) {
        player?.rate = rate
    }

    func currentTime() -> TimeInterval {
        player?.currentTime ?? 0
    }

    func duration() -> TimeInterval {
        player?.duration ?? 0
    }

    func isPlaying() -> Bool {
        player?.isPlaying ?? false
    }

    func stopPlayback() {
        player?.stop()
    }

    func reset() {
        player?.stop()
        player?.delegate = nil
        player = nil
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
    private(set) var channel: AudioChannel = .mic
    private(set) var availableChannels: [AudioChannel] = []
    private(set) var loadedURL: URL?

    var isPlaying: Bool { state == .playing }

    @ObservationIgnored private let engine = PlaybackEngine()
    @ObservationIgnored private var delegateBox: PlaybackDelegateBox?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    /// Serializes engine effects so ordered calls (seek then play) and a
    /// channel replacement apply in submission order.
    @ObservationIgnored private var controlTask: Task<Void, Never> = Task {}
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var micPath: String?
    @ObservationIgnored private var systemPath: String?

    func load(micPath: String?, systemPath: String?, preferred: AudioChannel? = nil) {
        cancelOpen()
        currentTime = 0
        duration = 0
        loadedURL = nil
        self.micPath = micPath
        self.systemPath = systemPath
        availableChannels = Self.channels(micPath: micPath, systemPath: systemPath)
        guard !availableChannels.isEmpty else {
            state = .idle
            return
        }
        let chosen: AudioChannel
        if let preferred, availableChannels.contains(preferred) {
            chosen = preferred
        } else if availableChannels.contains(.system) {
            chosen = .system
        } else {
            chosen = availableChannels[0]
        }
        channel = chosen
        openCurrentChannel(resumingAt: nil)
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
        state = .playing
        startTick()
        enqueue { engine in
            if restartsFromStart {
                await engine.seek(to: 0)
            }
            let started = await engine.play(rate: appliedRate)
            if !started, self.state == .playing {
                self.state = .failed(.loadFailed("Could not start playback"))
            }
        }
    }

    func pause() {
        guard state == .playing else { return }
        state = .paused
        tickTask?.cancel()
        tickTask = nil
        enqueue { engine in
            await engine.pause()
            self.currentTime = await engine.currentTime()
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

    func selectChannel(_ channel: AudioChannel) {
        guard channel != self.channel, availableChannels.contains(channel) else { return }
        let resumeTime = currentTime
        self.channel = channel
        openCurrentChannel(resumingAt: duration > 0 ? min(resumeTime, duration) : nil)
    }

    func stopAndRelease() {
        cancelOpen()
        micPath = nil
        systemPath = nil
        availableChannels = []
        loadedURL = nil
        currentTime = 0
        duration = 0
        state = .idle
        delegateBox?.controller = nil
        delegateBox = nil
        enqueue { engine in
            await engine.reset()
        }
    }

    // MARK: - Preparation

    private func openCurrentChannel(resumingAt resume: TimeInterval?) {
        let path: String?
        switch channel {
        case .mic: path = micPath
        case .system: path = systemPath
        }
        guard let path else {
            state = .idle
            return
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            state = .failed(.missingFile)
            return
        }
        generation += 1
        let current = generation
        let url = URL(fileURLWithPath: path)
        state = .preparing
        delegateBox?.controller = nil
        let box = PlaybackDelegateBox()
        box.controller = self
        delegateBox = box
        let appliedRate = rate
        enqueue { engine in
            do {
                let preparedDuration = try await engine.replace(
                    url: url, rate: appliedRate, delegate: box)
                guard current == self.generation else { return }
                self.loadedURL = url
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

    private func cancelOpen() {
        generation += 1
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - End of playback

    fileprivate func handleFinished(successfully: Bool) {
        tickTask?.cancel()
        tickTask = nil
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
        tickTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.state == .playing {
                let time = await self.engine.currentTime()
                let playerDuration = await self.engine.duration()
                let stillPlaying = await self.engine.isPlaying()
                self.currentTime = time
                if playerDuration > 0 {
                    self.duration = playerDuration
                }
                if !stillPlaying, self.state == .playing {
                    self.handleFinished(successfully: true)
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private static func channels(micPath: String?, systemPath: String?) -> [AudioChannel] {
        var result: [AudioChannel] = []
        if micPath != nil { result.append(.mic) }
        if systemPath != nil { result.append(.system) }
        return result
    }
}

/// AVAudioPlayer callbacks can arrive off the main actor; hop back in.
private final class PlaybackDelegateBox: NSObject, AVAudioPlayerDelegate, @unchecked Sendable {
    weak var controller: MeetingPlaybackController?

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
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
