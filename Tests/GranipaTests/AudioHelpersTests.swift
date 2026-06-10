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
}
