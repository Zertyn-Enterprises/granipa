import AVFoundation
import Accelerate

// Safe to send across isolation domains only because every chunk wraps a
// uniquely-owned buffer that is never mutated after creation.
struct AudioChunk: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    let startSeconds: Double?
}

extension AVAudioPCMBuffer {
    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        copy.frameLength = frameLength
        let source = UnsafeMutableAudioBufferListPointer(mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (src, dst) in zip(source, destination) {
            guard let srcData = src.mData, let dstData = dst.mData else { return nil }
            memcpy(dstData, srcData, Int(min(src.mDataByteSize, dst.mDataByteSize)))
        }
        return copy
    }

    var rmsLevel: Float {
        guard let channelData = floatChannelData, frameLength > 0 else { return 0 }
        let frames = vDSP_Length(frameLength)
        var total: Float = 0
        let channels = Int(format.channelCount)
        for channel in 0..<channels {
            var rms: Float = 0
            vDSP_rmsqv(channelData[channel], 1, &rms, frames)
            total += rms
        }
        return total / Float(channels)
    }
}
