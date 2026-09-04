import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct FileMeetingTranscriberTests {
    @Test func missingFilesLeaveNoSegments() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        var meeting = Meeting.new(title: "T", language: "en-US")
        try db.save(meeting)
        let missing = URL(fileURLWithPath: "/tmp/granipa-no-such-\(UUID().uuidString).m4a")
        await FileMeetingTranscriber.transcribe(
            micURL: missing,
            systemURL: missing,
            meetingID: meeting.id,
            language: "en-US",
            database: db)
        #expect((try db.fetchSegments(meetingID: meeting.id)).isEmpty)
    }
}
