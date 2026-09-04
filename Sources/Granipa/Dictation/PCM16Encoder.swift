import AVFoundation

enum PCM16Encoder {
    static func format24kMono() -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 24_000,
            channels: 1,
            interleaved: true)
    }

    static func data(from buffer: AVAudioPCMBuffer) -> Data? {
        let channels = Int(buffer.format.channelCount)
        if buffer.format.commonFormat == .pcmFormatInt16, channels == 1 {
            guard let pointer = buffer.int16ChannelData?[0] else { return nil }
            let byteCount = Int(buffer.frameLength) * MemoryLayout<Int16>.size
            return Data(bytes: pointer, count: byteCount)
        }
        guard let floatChannels = buffer.floatChannelData, buffer.frameLength > 0 else {
            return nil
        }
        let frames = Int(buffer.frameLength)
        var samples = [Int16](repeating: 0, count: frames)
        for frame in 0..<frames {
            var mixed: Float = 0
            for channel in 0..<channels {
                mixed += floatChannels[channel][frame]
            }
            mixed /= Float(max(channels, 1))
            let clipped = max(-1, min(1, mixed))
            samples[frame] = Int16((clipped * Float(Int16.max)).rounded())
        }
        return samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
