import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct MeetingExporterTests {
    @Test func markdownContainsAllSections() {
        var meeting = Meeting.new(title: "Roadmap sync", language: "en-US")
        meeting.summary = "We agreed the launch moves to July."
        meeting.enhancedNotesMarkdown = "## Decisions\n- Launch moved"
        meeting.actionItemsJSON = ActionItem.encodeList([
            ActionItem(text: "Send revised plan", owner: "Ana")
        ])
        meeting.emailDraft = "Hi all, quick recap."
        let folder = Folder.new(name: "Carbon", team: "Acme HQ")
        let segments = [
            TranscriptSegment.new(
                meetingID: meeting.id, channel: .mic, speaker: "Me",
                text: "hello there", startSeconds: 0, endSeconds: 2, isFinal: true)
        ]

        let markdown = MeetingExporter.markdown(
            meeting: meeting, segments: segments, folder: folder)

        #expect(markdown.hasPrefix("# Roadmap sync"))
        #expect(markdown.contains("Acme HQ / Carbon"))
        #expect(markdown.contains("## Summary"))
        #expect(markdown.contains("launch moves to July"))
        #expect(markdown.contains("- [ ] Send revised plan — Ana"))
        #expect(markdown.contains("## Transcript"))
        #expect(markdown.contains("[0:00] Me: hello there"))
    }

    @Test func markdownFallsBackToRawNotes() {
        var meeting = Meeting.new(title: "Quick note", language: "auto")
        meeting.notesMarkdown = "- remember the budget"
        let markdown = MeetingExporter.markdown(meeting: meeting, segments: [], folder: nil)
        #expect(markdown.contains("- remember the budget"))
        #expect(!markdown.contains("## Transcript"))
    }

    @Test func fileNameIsSanitized() {
        var meeting = Meeting.new(title: "Q3: plan / review?", language: "auto")
        #expect(MeetingExporter.suggestedFileName(for: meeting) == "Q3-plan-review.md")
        meeting.title = "///"
        #expect(MeetingExporter.suggestedFileName(for: meeting) == "Meeting.md")
    }

    @Test func renameSpeakerOnlyTouchesMatchingSegments() throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "T", language: "auto")
        try db.save(meeting)
        try db.save(
            TranscriptSegment.new(
                meetingID: meeting.id, channel: .system, speaker: "Speaker 1",
                text: "hola", startSeconds: 0, endSeconds: 1, isFinal: true))
        try db.save(
            TranscriptSegment.new(
                meetingID: meeting.id, channel: .system, speaker: "Speaker 2",
                text: "adios", startSeconds: 1, endSeconds: 2, isFinal: true))

        try db.renameSpeaker(meetingID: meeting.id, from: "Speaker 1", to: "María")

        let speakers = try db.fetchSegments(meetingID: meeting.id).map(\.speaker)
        #expect(speakers == ["María", "Speaker 2"])
    }
}
