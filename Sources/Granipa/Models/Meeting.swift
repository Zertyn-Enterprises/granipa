import Foundation
import GRDB

enum MeetingStatus: String, Codable, Sendable {
    case recording
    case processing
    case ready
}

struct Meeting: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var id: String
    var title: String
    var createdAt: Date
    var startedAt: Date?
    var endedAt: Date?
    var language: String
    var status: MeetingStatus
    var notesMarkdown: String
    var enhancedNotesMarkdown: String?
    var summary: String?
    var actionItemsJSON: String?
    var emailDraft: String?
    var templateID: String?
    var calendarEventID: String?
    var audioMicPath: String?
    var audioSystemPath: String?

    static func new(title: String, language: String) -> Meeting {
        Meeting(
            id: UUID().uuidString,
            title: title,
            createdAt: .now,
            startedAt: nil,
            endedAt: nil,
            language: language,
            status: .ready,
            notesMarkdown: "",
            enhancedNotesMarkdown: nil,
            summary: nil,
            actionItemsJSON: nil,
            emailDraft: nil,
            templateID: nil,
            calendarEventID: nil,
            audioMicPath: nil,
            audioSystemPath: nil
        )
    }
}
