import AVFoundation
import Foundation
import Testing

@testable import Granipa

enum TestMeetingAudio {
    static func writeTone(
        to url: URL,
        seconds: Double,
        sampleRate: Double = 22_050,
        frequency: Double = 440,
        amplitude: Float = 0.4
    ) throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
        else {
            throw NSError(
                domain: "TestMeetingAudio", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "could not build audio format"])
        }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames = AVAudioFrameCount((seconds * sampleRate).rounded())
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
            let data = buffer.floatChannelData
        else {
            throw NSError(
                domain: "TestMeetingAudio", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "could not allocate PCM buffer"])
        }
        buffer.frameLength = frames
        for frame in 0..<Int(frames) {
            data[0][frame] =
                amplitude * sin(2 * Float.pi * Float(frequency) * Float(frame) / Float(sampleRate))
        }
        try file.write(from: buffer)
        file.close()
    }

    static func writeSilence(to url: URL, seconds: Double) throws {
        try writeTone(to: url, seconds: seconds, frequency: 440, amplitude: 0)
    }
}

@Suite struct MeetingWaveformTests {
    @Test func decodeReadsRealPeaksAndBoundsMemoryToBarCount() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-wave-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestMeetingAudio.writeTone(to: url, seconds: 0.35)

        let peaks = try #require(MeetingWaveform.decode(url: url, barCount: 32))
        #expect(peaks.count == 32)
        #expect(peaks.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(peaks.max() ?? 0 > 0.2)
    }

    @Test func silenceAndMissingFilesAreHonest() throws {
        let silence = FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-wave-silence-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: silence) }
        try TestMeetingAudio.writeSilence(to: silence, seconds: 0.2)
        let peaks = try #require(MeetingWaveform.decode(url: silence, barCount: 16))
        #expect(peaks.allSatisfy { $0 < 0.02 })

        let missing = URL(fileURLWithPath: "/tmp/granipa-no-audio-\(UUID().uuidString).caf")
        #expect(MeetingWaveform.decode(url: missing) == nil)

        let junk = FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-wave-junk-\(UUID().uuidString).caf")
        defer { try? FileManager.default.removeItem(at: junk) }
        try Data("not audio".utf8).write(to: junk)
        #expect(MeetingWaveform.decode(url: junk) == nil)
    }
}

@Suite struct MeetingPlaybackTests {
    private func tempURL(_ suffix: String) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-play-\(suffix)-\(UUID().uuidString).caf")
    }

    @Test @MainActor func loadPlayPauseSeekRateAndEOFUseAVFoundation() async throws {
        let url = tempURL("tone")
        defer { try? FileManager.default.removeItem(at: url) }
        try TestMeetingAudio.writeTone(to: url, seconds: 0.45)

        let player = MeetingPlaybackController()
        player.load(micPath: url.path, systemPath: nil)
        #expect(player.state == .ready)
        #expect(player.channel == .mic)
        #expect(player.availableChannels == [.mic])
        #expect(player.duration > 0.35 && player.duration < 0.6)
        #expect(player.currentTime == 0)
        #expect(player.loadedURL?.path == url.path)

        player.play()
        #expect(player.state == .playing)
        try await Task.sleep(for: .milliseconds(80))
        #expect(player.currentTime > 0)

        player.pause()
        let pausedAt = player.currentTime
        #expect(player.state == .paused)
        try await Task.sleep(for: .milliseconds(60))
        #expect(abs(player.currentTime - pausedAt) < 0.05)

        player.seek(to: 0.12)
        #expect(abs(player.currentTime - 0.12) < 0.03)

        player.setRate(1.5)
        #expect(player.rate == 1.5)
        player.setRate(2)
        #expect(player.rate == 2)
        player.setRate(1)
        #expect(player.rate == 1)

        player.seek(to: max(0, player.duration - 0.05))
        player.play()
        var ended = false
        for _ in 0..<40 {
            if player.state == .ended {
                ended = true
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(ended)
        #expect(player.currentTime >= player.duration - 0.05)

        player.stopAndRelease()
        #expect(player.state == .idle)
        #expect(player.loadedURL == nil)
        #expect(player.duration == 0)
    }

    @Test @MainActor func missingAndCorruptFilesFailWithoutPlaying() {
        let player = MeetingPlaybackController()
        let missing = "/tmp/granipa-missing-\(UUID().uuidString).caf"
        player.load(micPath: missing, systemPath: nil)
        #expect(player.state == .failed(.missingFile))
        player.play()
        #expect(player.state == .failed(.missingFile))

        let junk = tempURL("junk")
        defer { try? FileManager.default.removeItem(at: junk) }
        try? Data("not audio".utf8).write(to: junk)
        player.load(micPath: junk.path, systemPath: nil)
        guard case .failed(.loadFailed) = player.state else {
            Issue.record("expected loadFailed, got \(player.state)")
            return
        }
    }

    @Test @MainActor func channelSwitchDoesNotMixAndDoesNotAutoplay() throws {
        let mic = tempURL("mic")
        let system = tempURL("system")
        defer {
            try? FileManager.default.removeItem(at: mic)
            try? FileManager.default.removeItem(at: system)
        }
        try TestMeetingAudio.writeTone(to: mic, seconds: 0.3, frequency: 440)
        try TestMeetingAudio.writeTone(to: system, seconds: 0.5, frequency: 660)

        let player = MeetingPlaybackController()
        player.load(micPath: mic.path, systemPath: system.path)
        #expect(player.state == .ready)
        #expect(!player.isPlaying)
        #expect(player.availableChannels == [.mic, .system])
        #expect(player.channel == .system)
        #expect(player.duration > 0.4)

        player.selectChannel(.mic)
        #expect(player.channel == .mic)
        #expect(!player.isPlaying)
        #expect(player.duration > 0.2 && player.duration < 0.4)
        #expect(player.loadedURL?.path == mic.path)

        player.play()
        #expect(player.isPlaying)
        player.selectChannel(.system)
        #expect(player.channel == .system)
        #expect(!player.isPlaying)
        #expect(player.loadedURL?.path == system.path)
    }

    @Test @MainActor func seekClampsAndLoadWithoutPathsStaysIdle() {
        let player = MeetingPlaybackController()
        player.load(micPath: nil, systemPath: nil)
        #expect(player.state == .idle)
        player.seek(to: 4)
        #expect(player.currentTime == 0)
    }
}
