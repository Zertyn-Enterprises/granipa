import AVFoundation
import Foundation
import Observation

enum MeetingPlaybackError: Equatable, Sendable {
    case missingFile
    case loadFailed(String)
}

enum MeetingPlaybackState: Equatable, Sendable {
    case idle
    case ready
    case playing
    case paused
    case ended
    case failed(MeetingPlaybackError)
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

    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var delegateBox: PlaybackDelegateBox?
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    @ObservationIgnored private var micPath: String?
    @ObservationIgnored private var systemPath: String?

    func load(micPath: String?, systemPath: String?, preferred: AudioChannel? = nil) {
        tearDownPlayer()
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
        openCurrentChannel()
    }

    func play() {
        guard let player else { return }
        switch state {
        case .failed, .idle:
            return
        case .ended:
            player.currentTime = 0
            currentTime = 0
        case .ready, .paused, .playing:
            break
        }
        player.rate = rate
        guard player.play() else {
            state = .failed(.loadFailed("Could not start playback"))
            return
        }
        state = .playing
        startTick()
    }

    func pause() {
        guard state == .playing else { return }
        player?.pause()
        syncFromPlayer()
        state = .paused
        tickTask?.cancel()
        tickTask = nil
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
        player?.currentTime = clamped
        currentTime = clamped
        if state == .ended, clamped < duration {
            state = .paused
        }
    }

    func setRate(_ rate: Float) {
        guard Self.rates.contains(rate) else { return }
        self.rate = rate
        player?.rate = rate
    }

    func selectChannel(_ channel: AudioChannel) {
        guard channel != self.channel, availableChannels.contains(channel) else { return }
        let resumeTime = currentTime
        let wasPlaying = isPlaying
        self.channel = channel
        tearDownPlayer()
        openCurrentChannel()
        if duration > 0 {
            seek(to: min(resumeTime, duration))
        }
        // Channel changes never autoplay — even if the previous file was playing.
        _ = wasPlaying
    }

    func stopAndRelease() {
        tearDownPlayer()
        micPath = nil
        systemPath = nil
        availableChannels = []
        loadedURL = nil
        currentTime = 0
        duration = 0
        state = .idle
    }

    private func openCurrentChannel() {
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
        let url = URL(fileURLWithPath: path)
        do {
            let audio = try AVAudioPlayer(contentsOf: url)
            audio.enableRate = true
            audio.rate = rate
            let box = PlaybackDelegateBox()
            box.controller = self
            audio.delegate = box
            audio.prepareToPlay()
            player = audio
            delegateBox = box
            loadedURL = url
            duration = audio.duration
            currentTime = 0
            state = .ready
        } catch {
            state = .failed(.loadFailed(error.localizedDescription))
        }
    }

    fileprivate func handleFinished(successfully: Bool) {
        tickTask?.cancel()
        tickTask = nil
        if successfully {
            currentTime = duration
            state = .ended
        } else {
            syncFromPlayer()
            state = .paused
        }
    }

    fileprivate func handleDecodeError(_ message: String) {
        tickTask?.cancel()
        tickTask = nil
        player?.stop()
        state = .failed(.loadFailed(message))
    }

    private func startTick() {
        tickTask?.cancel()
        tickTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled, self.state == .playing {
                self.syncFromPlayer()
                if let player = self.player, !player.isPlaying, self.state == .playing {
                    self.handleFinished(successfully: true)
                    break
                }
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func syncFromPlayer() {
        guard let player else { return }
        currentTime = player.currentTime
        if player.duration > 0 {
            duration = player.duration
        }
    }

    private func tearDownPlayer() {
        tickTask?.cancel()
        tickTask = nil
        player?.stop()
        player?.delegate = nil
        player = nil
        delegateBox?.controller = nil
        delegateBox = nil
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
