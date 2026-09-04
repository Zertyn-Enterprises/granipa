import AVFoundation

/// Silence gate for a live analyzer feed. Speech opens the gate; a hangover
/// keeps it open through short pauses so word tails aren't clipped. Omitting
/// the silent buffers is the documented way to keep an idle analyzer idle;
/// the resume buffer re-stamps the timeline via `bufferStartTime` (see
/// `transcribeChannel`). Both meeting channels stamp `startSeconds`.
struct SpeechGate {
    /// Same level the session counts as a non-silent buffer.
    static let nonSilentThreshold: Float = 0.0005
    /// Seconds of silence still fed after the last speech buffer.
    static let hangoverSeconds: Double = 0.4

    private let threshold: Float
    private let hangover: Double
    private var opened = false
    private var silentSeconds: Double = 0

    init(
        threshold: Float = SpeechGate.nonSilentThreshold,
        hangover: Double = SpeechGate.hangoverSeconds
    ) {
        self.threshold = threshold
        self.hangover = hangover
    }

    mutating func admits(_ chunk: AudioChunk) -> Bool {
        let duration = Double(chunk.buffer.frameLength) / chunk.buffer.format.sampleRate
        if chunk.buffer.rmsLevel > threshold {
            opened = true
            silentSeconds = 0
            return true
        }
        // Silence only passes as the tail of speech, never on its own.
        guard opened else { return false }
        silentSeconds += duration
        return silentSeconds <= hangover
    }
}
