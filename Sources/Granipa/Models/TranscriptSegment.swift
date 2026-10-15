import Foundation
import GRDB

enum AudioChannel: String, Codable, Sendable {
    case mic
    case system
}

/// One recognized word with its meeting-relative audio span.
struct TranscriptWord: Codable, Hashable, Sendable {
    var text: String
    var start: Double
    var end: Double
}

struct TranscriptSegment: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var id: String
    var meetingID: String
    var channel: AudioChannel
    var speaker: String
    var text: String
    var startSeconds: Double
    var endSeconds: Double
    var isFinal: Bool
    /// Per-word timing from the recognizer; nil for segments recorded before
    /// it was stored. Kept out of the public API.
    var words: [TranscriptWord]? = nil

    static func new(
        meetingID: String,
        channel: AudioChannel,
        speaker: String,
        text: String,
        startSeconds: Double,
        endSeconds: Double,
        isFinal: Bool,
        words: [TranscriptWord]? = nil
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: UUID().uuidString,
            meetingID: meetingID,
            channel: channel,
            speaker: speaker,
            text: text,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            isFinal: isFinal,
            words: words
        )
    }
}
