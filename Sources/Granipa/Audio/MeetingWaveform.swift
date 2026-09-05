import AVFoundation
import Foundation

enum MeetingWaveform {
    static let barCount = 128
    static let windowFrames: AVAudioFrameCount = 2_048

    /// Peak envelope sampled in a bounded number of windows. Returns nil when
    /// the file is missing, unreadable, or empty — callers show a plain slider.
    static func decode(url: URL, barCount: Int = barCount) -> [Float]? {
        let bars = max(1, barCount)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            return nil
        }
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let total = file.length
            guard total > 0 else { return nil }
            let window = AVAudioFrameCount(min(Int64(windowFrames), total))
            guard window > 0,
                let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: window)
            else {
                return nil
            }

            var peaks = [Float](repeating: 0, count: bars)
            let channels = Int(format.channelCount)
            for bar in 0..<bars {
                file.framePosition = Int64(bar) * total / Int64(bars)
                try file.read(into: buffer, frameCount: window)
                let length = Int(buffer.frameLength)
                guard length > 0, let samples = buffer.floatChannelData else { continue }
                var peak: Float = 0
                for channel in 0..<channels {
                    let data = samples[channel]
                    for index in 0..<length {
                        peak = max(peak, abs(data[index]))
                    }
                }
                peaks[bar] = min(1, peak)
            }
            return peaks
        } catch {
            return nil
        }
    }
}
