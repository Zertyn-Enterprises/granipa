import Foundation

/// Maps raw speech RMS onto a 0…1 waveform bar height.
///
/// Mic speech hovers around RMS 0.005–0.08, so a linear scale renders as a
/// row of dots: a compressive power curve lifts quiet speech into a visible
/// mid-range while loud peaks clamp at full height.
enum WaveformGain {
    static func display(_ rms: Float) -> Float {
        guard rms.isFinite, rms > 0 else { return 0 }
        return min(1, pow(rms * 14, 0.45))
    }
}

enum WaveformEnvelope {
    static func next(current: Float, target: Float) -> Float {
        guard current.isFinite, target.isFinite else { return 0 }
        let boundedCurrent = min(1, max(0, current))
        let boundedTarget = min(1, max(0, target))
        let response: Float = boundedTarget > boundedCurrent ? 0.65 : 0.25
        return boundedCurrent + (boundedTarget - boundedCurrent) * response
    }
}
