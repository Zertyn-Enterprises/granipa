import Foundation
import GRDB

enum AudioChannel: String, Codable, Sendable {
    case mic
    case system
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

    static func new(
        meetingID: String,
        channel: AudioChannel,
        speaker: String,
        text: String,
        startSeconds: Double,
        endSeconds: Double,
        isFinal: Bool
    ) -> TranscriptSegment {
        TranscriptSegment(
            id: UUID().uuidString,
            meetingID: meetingID,
            channel: channel,
            speaker: speaker,
            text: text,
            startSeconds: startSeconds,
            endSeconds: endSeconds,
            isFinal: isFinal
        )
    }
}
