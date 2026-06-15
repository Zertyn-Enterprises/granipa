import AVFoundation
import Testing

@testable import Granipa

@Suite struct AudioHelpersTests {
    private func makeBuffer(samples: [Float], sampleRate: Double = 48_000) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        for (i, sample) in samples.enumerated() {
            buffer.floatChannelData![0][i] = sample
        }
        return buffer
    }

    @Test func rmsOfSilenceIsZero() {
        let buffer = makeBuffer(samples: [Float](repeating: 0, count: 1024))
        #expect(buffer.rmsLevel == 0)
    }

    @Test func rmsOfConstantSignal() {
        let buffer = makeBuffer(samples: [Float](repeating: 0.5, count: 1024))
        #expect(abs(buffer.rmsLevel - 0.5) < 0.0001)
    }

    @Test func deepCopyIsIndependent() throws {
        let buffer = makeBuffer(samples: [0.1, 0.2, 0.3, 0.4])
        let copy = try #require(buffer.deepCopy())
        #expect(copy.frameLength == 4)
        #expect(copy.floatChannelData![0][2] == 0.3)

        buffer.floatChannelData![0][2] = 0.9
        #expect(copy.floatChannelData![0][2] == 0.3)
    }

    @Test func converterAdaptsWhenInputFormatChanges() throws {
        // Regression: a device switch changes the input format mid-stream. The
        // converter must rebuild for the new input instead of failing every buffer
        // and silently killing the channel's transcription.
        let target = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let converter = BufferConverter()

        let first = makeBuffer(samples: [Float](repeating: 0.2, count: 480), sampleRate: 48_000)
        let firstOut = try converter.convert(first, to: target)
        #expect(firstOut.format.sampleRate == 16_000)

        let second = makeBuffer(samples: [Float](repeating: 0.2, count: 441), sampleRate: 44_100)
        let secondOut = try converter.convert(second, to: target)
        #expect(secondOut.format.sampleRate == 16_000)
    }
}
