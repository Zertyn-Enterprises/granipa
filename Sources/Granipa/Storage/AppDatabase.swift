import Foundation
import GRDB

struct AppDatabase: Sendable {
    let writer: any DatabaseWriter

    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    static func open() throws -> AppDatabase {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("Granipa", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let queue = try DatabaseQueue(path: dir.appendingPathComponent("granipa.sqlite").path)
        return try AppDatabase(writer: queue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "meeting") { t in
                t.primaryKey("id", .text)
                t.column("title", .text).notNull()
                t.column("createdAt", .datetime).notNull()
                t.column("startedAt", .datetime)
                t.column("endedAt", .datetime)
                t.column("language", .text).notNull()
                t.column("status", .text).notNull()
                t.column("notesMarkdown", .text).notNull()
                t.column("enhancedNotesMarkdown", .text)
                t.column("summary", .text)
                t.column("actionItemsJSON", .text)
                t.column("emailDraft", .text)
                t.column("templateID", .text)
                t.column("calendarEventID", .text)
                t.column("audioMicPath", .text)
                t.column("audioSystemPath", .text)
            }
            try db.create(table: "transcriptSegment") { t in
                t.primaryKey("id", .text)
                t.column("meetingID", .text).notNull().indexed()
                    .references("meeting", onDelete: .cascade)
                t.column("channel", .text).notNull()
                t.column("speaker", .text).notNull()
                t.column("text", .text).notNull()
                t.column("startSeconds", .double).notNull()
                t.column("endSeconds", .double).notNull()
                t.column("isFinal", .boolean).notNull()
            }
        }
        return migrator
    }
}

extension AppDatabase {
    func fetchMeetings() throws -> [Meeting] {
        try writer.read { db in
            try Meeting.order(Column("createdAt").desc).fetchAll(db)
        }
    }

    func fetchMeeting(id: String) throws -> Meeting? {
        try writer.read { db in try Meeting.fetchOne(db, key: id) }
    }

    func save(_ meeting: Meeting) throws {
        try writer.write { db in try meeting.save(db) }
    }

    func deleteMeeting(id: String) throws {
        _ = try writer.write { db in try Meeting.deleteOne(db, key: id) }
    }

    func fetchSegments(meetingID: String, finalOnly: Bool = false) throws -> [TranscriptSegment] {
        try writer.read { db in
            var request = TranscriptSegment
                .filter(Column("meetingID") == meetingID)
                .order(Column("startSeconds"))
            if finalOnly {
                request = request.filter(Column("isFinal") == true)
            }
            return try request.fetchAll(db)
        }
    }

    func save(_ segment: TranscriptSegment) throws {
        try writer.write { db in try segment.save(db) }
    }

    func replaceSegments(meetingID: String, channel: AudioChannel, with segments: [TranscriptSegment]) throws {
        try writer.write { db in
            try TranscriptSegment
                .filter(Column("meetingID") == meetingID)
                .filter(Column("channel") == channel.rawValue)
                .deleteAll(db)
            for segment in segments {
                try segment.save(db)
            }
        }
    }
}
