import AVFoundation
import Accelerate
import Foundation
import Testing

@testable import Granipa

/// Regression: switching the default input mid-meeting (AirPods in/out, a wired
/// headset, a USB mic) used to recreate mic.m4a, replacing everything already
/// recorded with silence, and buffers from the new device can arrive at a
/// different sample rate / channel count than the file was opened with. The
/// file must keep its earlier audio, keep its original format, and keep file
/// time equal to meeting time (gaps padded with silence).
@Suite struct MicContinuityTests {
#if DEBUG
    // These drive the DEBUG-only ingestMicBufferForTesting seam.
    private func tone(
        sampleRate: Double, channels: UInt32, seconds: Double, amplitude: Float
    ) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: channels)!
        let frames = AVAudioFrameCount((seconds * sampleRate).rounded())
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<Int(channels) {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData![channel][frame] =
                    amplitude * sin(2 * Float.pi * 440 * Float(frame) / Float(sampleRate))
            }
        }
        return buffer
    }

    private func makeSession(directory: URL) -> RecordingSession {
        RecordingSession(
            meetingID: "mic-continuity", directory: directory, fanOutChunks: false
        ) { _, _ in }
    }

    private func readMicAudio(from url: URL) throws -> (
        buffer: AVAudioPCMBuffer, format: AVAudioFormat
    ) {
        let file = try AVAudioFile(forReading: url)
        let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length))!
        try file.read(into: buffer)
        return (buffer, file.processingFormat)
    }

    private func rms(_ buffer: AVAudioPCMBuffer, seconds: Range<Double>) -> Float {
        let rate = buffer.format.sampleRate
        let lower = Int((seconds.lowerBound * rate).rounded())
        let upper = min(Int((seconds.upperBound * rate).rounded()), Int(buffer.frameLength))
        guard let data = buffer.floatChannelData, upper > lower else { return 0 }
        var value: Float = 0
        vDSP_rmsqv(data[0] + lower, 1, &value, vDSP_Length(upper - lower))
        return value
    }

    @Test func defaultInputChangePreservesEarlierAudioAndAppendsNewFormat() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mic-continuity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(directory: directory)

        // Pre-change: built-in mic delivers 48 kHz mono for half a second.
        session.ingestMicBufferForTesting(
            tone(sampleRate: 48_000, channels: 1, seconds: 0.5, amplitude: 0.5), startSeconds: 0)
        // The default input switches mid-meeting. The hardware listener cannot
        // fire in a test (no second device, no mic TCC), so the seam injects
        // its observable effect: a short gap, then buffers in a new format.
        session.ingestMicBufferForTesting(
            tone(sampleRate: 44_100, channels: 2, seconds: 0.5, amplitude: 0.4), startSeconds: 0.6)
        await session.stop()

        let (audio, format) = try readMicAudio(from: session.micURL)
        #expect(format.sampleRate == 48_000)
        #expect(format.channelCount == 1)
        let duration = Double(audio.frameLength) / format.sampleRate
        #expect(duration > 0.9 && duration < 1.3)
        // The half second captured before the switch must still be there.
        #expect(rms(audio, seconds: 0..<0.25) > 0.3)
        // The new device's audio must be appended, not dropped.
        #expect(rms(audio, seconds: 0.8..<1.0) > 0.2)
    }

    @Test func gapBeforeNewDeviceAudioIsPaddedWithSilence() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mic-continuity-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = makeSession(directory: directory)

        session.ingestMicBufferForTesting(
            tone(sampleRate: 48_000, channels: 1, seconds: 0.5, amplitude: 0.5), startSeconds: 0)
        // The restarted mic resumes three seconds into the meeting with a
        // different format; the restart gap must become silence.
        session.ingestMicBufferForTesting(
            tone(sampleRate: 44_100, channels: 2, seconds: 0.5, amplitude: 0.4), startSeconds: 3)
        await session.stop()

        let (audio, format) = try readMicAudio(from: session.micURL)
        #expect(format.sampleRate == 48_000)
        #expect(format.channelCount == 1)
        let duration = Double(audio.frameLength) / format.sampleRate
        #expect(duration > 3.3 && duration < 3.8)
        #expect(rms(audio, seconds: 0..<0.25) > 0.3)
        #expect(rms(audio, seconds: 1.0..<2.0) < 0.02)
        #expect(rms(audio, seconds: 3.3..<3.5) > 0.2)
    }
#endif

    /// The one piece of the fix a hardware-free test cannot drive is the
    /// default-input listener itself: firing it needs a real route change
    /// (second input device) and the mic TCC grant. The writer-path behavior
    /// above stays behavioral; pin the listener's wiring as a narrow source
    /// contract instead. This fails against the pre-fix source (which called
    /// `restartMic(recreateFile: true)` straight from the listener and wiped
    /// mic.m4a) and against anyone flipping the flag back.
    @Test func defaultInputListenerRestartsTheMicWithoutRecreatingItsFile() throws {
        let source = try Self.recordingSessionSource()

        // The default-input listener must route through the file-preserving
        // wrapper, never straight into restartMic.
        let listener = try #require(
            Self.braceFreeBody(after: "inputBlock: AudioObjectPropertyListenerBlock = {", in: source))
        #expect(listener.contains("restartMicForDefaultInputChange()"))
        #expect(!listener.contains("restartMic(recreateFile:"))

        // And the wrapper must restart without recreating the mic file.
        let wrapper = try #require(
            Self.braceFreeBody(
                after: "private func restartMicForDefaultInputChange() {", in: source))
        #expect(wrapper.contains("restartMic(recreateFile: false)"))
        #expect(!wrapper.contains("recreateFile: true"))
    }

    private static func recordingSessionSource() throws -> String {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repo.appendingPathComponent("Sources/Granipa/Audio/RecordingSession.swift"),
            encoding: .utf8)
    }

    /// Source between `anchor` and the next `}` — enough to assert on the
    /// single-statement closure/function bodies above without regexing the
    /// whole file. Returns nil when the anchor (or its body) is gone.
    private static func braceFreeBody(after anchor: String, in source: String) -> Substring? {
        guard let anchorRange = source.range(of: anchor) else { return nil }
        let start = anchorRange.upperBound
        guard let end = source[start...].firstIndex(of: "}") else { return nil }
        return source[start..<end]
    }
}
