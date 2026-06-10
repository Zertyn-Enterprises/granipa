import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct AppDatabaseTests {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    @Test func meetingRoundTrip() throws {
        let db = try makeDatabase()
        var meeting = Meeting.new(title: "Weekly sync", language: "en-US")
        meeting.notesMarkdown = "- talked about roadmap"
        try db.save(meeting)

        let fetched = try #require(try db.fetchMeeting(id: meeting.id))
        #expect(fetched.id == meeting.id)
        #expect(fetched.title == meeting.title)
        #expect(fetched.notesMarkdown == meeting.notesMarkdown)
        #expect(abs(fetched.createdAt.timeIntervalSince(meeting.createdAt)) < 0.001)
        #expect(try db.fetchMeetings().count == 1)
    }

    @Test func segmentsOrderedAndFiltered() throws {
        let db = try makeDatabase()
        let meeting = Meeting.new(title: "Test", language: "es-ES")
        try db.save(meeting)

        let second = TranscriptSegment.new(
            meetingID: meeting.id, channel: .system, speaker: "Them",
            text: "hola", startSeconds: 5.0, endSeconds: 7.0, isFinal: true)
        let first = TranscriptSegment.new(
            meetingID: meeting.id, channel: .mic, speaker: "Me",
            text: "hello", startSeconds: 1.0, endSeconds: 3.0, isFinal: false)
        try db.save(second)
        try db.save(first)

        let all = try db.fetchSegments(meetingID: meeting.id)
        #expect(all.map(\.text) == ["hello", "hola"])

        let finals = try db.fetchSegments(meetingID: meeting.id, finalOnly: true)
        #expect(finals.map(\.text) == ["hola"])
    }

    @Test func searchFindsTitleNotesAndTranscript() throws {
        let db = try makeDatabase()
        var byTitle = Meeting.new(title: "Quarterly Roadmap", language: "en-US")
        try db.save(byTitle)
        let byTranscript = Meeting.new(title: "Untitled meeting", language: "es-ES")
        try db.save(byTranscript)
        try db.save(
            TranscriptSegment.new(
                meetingID: byTranscript.id, channel: .system, speaker: "Them",
                text: "hablemos del presupuesto", startSeconds: 0, endSeconds: 2, isFinal: true))
        byTitle.notesMarkdown = "remember the budget"
        try db.save(byTitle)

        #expect(try db.searchMeetings(query: "roadmap").map(\.id) == [byTitle.id])
        #expect(try db.searchMeetings(query: "presupuesto").map(\.id) == [byTranscript.id])
        #expect(try db.searchMeetings(query: "budget").map(\.id) == [byTitle.id])
        #expect(try db.searchMeetings(query: "100%").isEmpty)
    }

    @Test func deleteCascadesToSegments() throws {
        let db = try makeDatabase()
        let meeting = Meeting.new(title: "Test", language: "en-US")
        try db.save(meeting)
        try db.save(
            TranscriptSegment.new(
                meetingID: meeting.id, channel: .mic, speaker: "Me",
                text: "bye", startSeconds: 0, endSeconds: 1, isFinal: true))

        try db.deleteMeeting(id: meeting.id)
        #expect(try db.fetchSegments(meetingID: meeting.id).isEmpty)
    }

    @Test func replaceSegmentsOnlyTouchesChannel() throws {
        let db = try makeDatabase()
        let meeting = Meeting.new(title: "Test", language: "en-US")
        try db.save(meeting)
        try db.save(
            TranscriptSegment.new(
                meetingID: meeting.id, channel: .mic, speaker: "Me",
                text: "mine", startSeconds: 0, endSeconds: 1, isFinal: true))
        try db.save(
            TranscriptSegment.new(
                meetingID: meeting.id, channel: .system, speaker: "Them",
                text: "old", startSeconds: 1, endSeconds: 2, isFinal: true))

        let replacement = TranscriptSegment.new(
            meetingID: meeting.id, channel: .system, speaker: "Speaker 1",
            text: "new", startSeconds: 1, endSeconds: 2, isFinal: true)
        try db.replaceSegments(meetingID: meeting.id, channel: .system, with: [replacement])

        let all = try db.fetchSegments(meetingID: meeting.id)
        #expect(all.map(\.text) == ["mine", "new"])
        #expect(all.map(\.speaker) == ["Me", "Speaker 1"])
    }
}
