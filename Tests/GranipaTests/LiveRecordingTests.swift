import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct LiveStageStateTests {
    @Test func startingMapsToStarting() {
        #expect(
            LiveStage.state(isRecording: false, isStarting: true, transcriptionPhase: nil)
                == .starting)
        #expect(
            LiveStage.state(isRecording: false, isStarting: true, transcriptionPhase: .live)
                == .starting)
    }

    @Test func recordingMapsNilPreparingAndLiveToRecording() {
        #expect(
            LiveStage.state(isRecording: true, isStarting: false, transcriptionPhase: nil)
                == .recording)
        #expect(
            LiveStage.state(isRecording: true, isStarting: false, transcriptionPhase: .live)
                == .recording)
        #expect(
            LiveStage.state(isRecording: true, isStarting: true, transcriptionPhase: .preparing)
                == .recording)
    }

    @Test func liveFailureStillCaptures() {
        let state = LiveStage.state(
            isRecording: true, isStarting: false, transcriptionPhase: .failed("model missing"))
        #expect(state == .transcriptionFailed("model missing"))
        #expect(state?.isCapturing == true)
    }

    @Test func onlyStartingCapturesNothing() {
        #expect(LiveStageState.starting.isCapturing == false)
        #expect(LiveStageState.recording.isCapturing == true)
    }

    @Test func idleHidesTheStage() {
        #expect(
            LiveStage.state(isRecording: false, isStarting: false, transcriptionPhase: .live)
                == nil)
    }
}

@Suite struct LiveStageFormatTests {
    @Test func elapsedFormatting() {
        #expect(LiveStageFormat.elapsed(0) == "0:00")
        #expect(LiveStageFormat.elapsed(9) == "0:09")
        #expect(LiveStageFormat.elapsed(65) == "1:05")
        #expect(LiveStageFormat.elapsed(599) == "9:59")
        #expect(LiveStageFormat.elapsed(3599) == "59:59")
        #expect(LiveStageFormat.elapsed(3600) == "01:00:00")
        #expect(LiveStageFormat.elapsed(3661) == "01:01:01")
        #expect(LiveStageFormat.elapsed(45294) == "12:34:54")
        #expect(LiveStageFormat.elapsed(-5) == "0:00")
    }
}

@Suite struct LevelHistoryTests {
    @Test func clampsAndKeepsMostRecent() {
        var history = LevelHistory(capacity: 4)
        for level in [0.1 as Float, 1.7, -0.2, 0.5, 0.9] {
            history.append(level)
        }
        #expect(history.samples == [1.0, 0.0, 0.5, 0.9])
    }

    @Test func startsEmpty() {
        #expect(LevelHistory().samples.isEmpty)
        #expect(LevelHistory().capacity == 64)
    }
}

@Suite struct LiveStageLayoutTests {
    @Test func twoColumnThreshold() {
        #expect(!LiveStageLayout.isTwoColumn(width: 712))
        #expect(!LiveStageLayout.isTwoColumn(width: 732))
        #expect(!LiveStageLayout.isTwoColumn(width: 879))
        #expect(LiveStageLayout.isTwoColumn(width: 880))
        #expect(LiveStageLayout.isTwoColumn(width: 964))
    }
}

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
