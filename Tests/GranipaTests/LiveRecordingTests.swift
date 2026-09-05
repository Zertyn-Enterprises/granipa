import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct MeetingEditorMergeTests {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    /// Regression guard for the stale editor snapshot: a debounced save that
    /// fires after Stop must not roll status/endedAt/audio paths back to the
    /// pre-stop values the editor copied at init.
    @Test func editorEditsMergeOntoPipelineWrites() throws {
        let db = try makeDatabase()
        let folder = Folder.new(name: "Team", team: nil)
        try db.save(folder)
        try db.save(
            MeetingTemplate(id: "template-2", name: "Retro", prompt: "p", isBuiltin: false))
        var recording = Meeting.new(title: "Weekly sync", language: "es-ES")
        recording.status = .recording
        recording.startedAt = Date(timeIntervalSince1970: 100)
        try db.save(recording)

        // Stop landed while the editor was open.
        var stopped = recording
        stopped.status = .processing
        stopped.endedAt = Date(timeIntervalSince1970: 400)
        stopped.audioMicPath = "/tmp/mic.m4a"
        stopped.audioSystemPath = "/tmp/system.m4a"
        try db.save(stopped)

        // The debounced save fires with the stale editor copy.
        var edited = recording
        edited.title = "Renamed sync"
        edited.notesMarkdown = "decision: ship friday"
        edited.folderID = folder.id
        edited.templateID = "template-2"
        try db.save(Meeting.mergingEditorEdits(edited, into: stopped))

        let fetched = try #require(try db.fetchMeeting(id: recording.id))
        #expect(fetched.title == "Renamed sync")
        #expect(fetched.notesMarkdown == "decision: ship friday")
        #expect(fetched.folderID == folder.id)
        #expect(fetched.templateID == "template-2")
        #expect(fetched.status == .processing)
        #expect(abs(fetched.endedAt!.timeIntervalSince(stopped.endedAt!)) < 0.001)
        #expect(fetched.audioMicPath == "/tmp/mic.m4a")
        #expect(fetched.audioSystemPath == "/tmp/system.m4a")
        #expect(abs(fetched.startedAt!.timeIntervalSince(recording.startedAt!)) < 0.001)
    }

    @Test func mergeKeepsEnhancementOutput() {
        var current = Meeting.new(title: "Standup", language: "en-US")
        current.summary = "pipeline summary"
        current.enhancedNotesMarkdown = "## enhanced"
        current.actionItemsJSON = "[]"
        current.emailDraft = "draft"
        var edited = current
        edited.title = "Standup — Q3"
        let merged = Meeting.mergingEditorEdits(edited, into: current)
        #expect(merged.title == "Standup — Q3")
        #expect(merged.summary == "pipeline summary")
        #expect(merged.enhancedNotesMarkdown == "## enhanced")
        #expect(merged.actionItemsJSON == "[]")
        #expect(merged.emailDraft == "draft")
    }
}
