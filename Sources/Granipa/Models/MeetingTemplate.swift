import Foundation
import GRDB

struct MeetingTemplate: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var id: String
    var name: String
    var prompt: String
    var isBuiltin: Bool

    static let builtins: [MeetingTemplate] = [
        MeetingTemplate(
            id: "builtin-general",
            name: "General",
            prompt: """
                Structure the notes with these sections (omit empty ones): \
                Key points, Decisions, Open questions.
                """,
            isBuiltin: true),
        MeetingTemplate(
            id: "builtin-one-on-one",
            name: "1:1",
            prompt: """
                This is a one-on-one meeting. Focus on: personal and project updates, \
                feedback given and received, growth or career topics, and agreed actions. \
                Keep a section per person.
                """,
            isBuiltin: true),
        MeetingTemplate(
            id: "builtin-standup",
            name: "Standup",
            prompt: """
                This is a team standup. For each participant capture: what they did, \
                what they will do next, and blockers. Highlight blockers prominently.
                """,
            isBuiltin: true),
        MeetingTemplate(
            id: "builtin-sales",
            name: "Sales call",
            prompt: """
                This is a sales call. Capture: prospect needs and pain points, objections \
                raised and how they were handled, pricing or commercial discussion, \
                competitors mentioned, deal stage, and concrete next steps with dates.
                """,
            isBuiltin: true),
    ]
}
