import AVFoundation
import Testing

@testable import Granipa

@Suite struct SpeechGateTests {
    private func chunk(amp: Float, seconds: Double) -> AudioChunk {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let frames = AVAudioFrameCount(seconds * 48_000)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        if let data = buffer.floatChannelData {
            for frame in 0..<Int(frames) {
                data[0][frame] = amp
            }
        }
        return AudioChunk(buffer: buffer, startSeconds: 0)
    }

    @Test func silenceNeverAdmits() {
        var gate = SpeechGate()
        for _ in 0..<20 {
            let admitted = gate.admits(chunk(amp: 0, seconds: 0.1))
            #expect(admitted == false)
        }
    }

    @Test func speechOpensGateAndHangoverHoldsItBriefly() {
        var gate = SpeechGate()
        var admitted = gate.admits(chunk(amp: 0.01, seconds: 0.1))
        #expect(admitted)
        // 0.2s of trailing silence stays inside the 0.4s hangover…
        admitted = gate.admits(chunk(amp: 0, seconds: 0.1))
        #expect(admitted)
        admitted = gate.admits(chunk(amp: 0, seconds: 0.1))
        #expect(admitted)
        // …a full second of silence closes it.
        admitted = gate.admits(chunk(amp: 0, seconds: 0.5))
        #expect(admitted == false)
        admitted = gate.admits(chunk(amp: 0, seconds: 0.5))
        #expect(admitted == false)
    }

    @Test func speechAfterClosureReopensGate() {
        var gate = SpeechGate()
        var admitted = gate.admits(chunk(amp: 0.01, seconds: 0.1))
        #expect(admitted)
        admitted = gate.admits(chunk(amp: 0, seconds: 0.5))
        #expect(admitted == false)
        admitted = gate.admits(chunk(amp: 0, seconds: 0.5))
        #expect(admitted == false)
        admitted = gate.admits(chunk(amp: 0.01, seconds: 0.1))
        #expect(admitted)
        // Hangover restarted by the new speech.
        admitted = gate.admits(chunk(amp: 0, seconds: 0.1))
        #expect(admitted)
    }

    @Test func subThresholdAudioDoesNotOpenGate() {
        var gate = SpeechGate()
        // 0.0005 is the session's non-silent line; below it is comfort noise.
        var admitted = gate.admits(chunk(amp: 0.0001, seconds: 0.1))
        #expect(admitted == false)
        admitted = gate.admits(chunk(amp: 0.0004, seconds: 0.1))
        #expect(admitted == false)
    }
}
