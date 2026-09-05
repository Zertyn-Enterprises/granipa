import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct MeetingHeaderMetaTests {
    private let created = Date(timeIntervalSince1970: 1_750_000_000)
    private let started = Date(timeIntervalSince1970: 1_750_000_000)
    private let ended = Date(timeIntervalSince1970: 1_750_000_075)

    @Test func dateDurationLanguageFolderAndRecordedComeFromRealFields() {
        let items = MeetingHeaderMeta.items(
            createdAt: created,
            startedAt: started,
            endedAt: ended,
            language: "es-ES",
            folderName: "Product",
            phase: .ready,
            hasAudio: true)
        #expect(items.contains { $0.systemImage == "calendar" && !$0.text.isEmpty })
        #expect(items.contains { $0.text == "1:15" && $0.systemImage == "clock" })
        #expect(items.contains { $0.text == "ES" && $0.systemImage == "globe" })
        #expect(items.contains { $0.text == "Product" && $0.systemImage == "folder" })
        #expect(items.contains { $0.text == "Recorded" && $0.systemImage == "checkmark.circle.fill" })
    }

    @Test func autoLanguageAndMissingFolderAreOmitted() {
        let items = MeetingHeaderMeta.items(
            createdAt: created,
            startedAt: nil,
            endedAt: nil,
            language: "auto",
            folderName: nil,
            phase: .idle,
            hasAudio: false)
        #expect(!items.contains { $0.systemImage == "globe" })
        #expect(!items.contains { $0.systemImage == "folder" })
        #expect(!items.contains { $0.systemImage == "clock" })
        #expect(!items.contains { $0.text == "Recorded" })
        #expect(items.contains { $0.systemImage == "calendar" })
    }

    @Test func livePhaseWinsOverRecordedChip() {
        let items = MeetingHeaderMeta.items(
            createdAt: created,
            startedAt: started,
            endedAt: nil,
            language: "auto",
            folderName: nil,
            phase: .recording,
            hasAudio: true)
        #expect(items.contains { $0.text == "Recording" })
        #expect(!items.contains { $0.text == "Recorded" })
    }

    @Test func tabCountShowsActualActionItemsOnly() {
        #expect(MeetingTabAccessory.actionItemCountLabel(0) == nil)
        #expect(MeetingTabAccessory.actionItemCountLabel(4) == "4")
    }
}

@Suite struct OverviewPreviewTests {
    @Test func emptyAndWhitespaceAreNotPreviewed() {
        #expect(OverviewPreview.snippet(nil) == nil)
        #expect(OverviewPreview.snippet("  \n  ") == nil)
        #expect(OverviewPreview.snippet("") == nil)
    }

    @Test func shortNotesPassThrough() {
        #expect(OverviewPreview.snippet("ship friday") == "ship friday")
    }

    @Test func longNotesTruncateOnAWordBoundary() throws {
        let words = Array(repeating: "alpha", count: 80).joined(separator: " ")
        let snippet = try #require(OverviewPreview.snippet(words, limit: 40))
        #expect(snippet.hasSuffix("…"))
        #expect(snippet.count < words.count)
        #expect(!snippet.contains("  "))
        #expect(snippet.contains("alpha"))
    }

    @Test func summaryIsNotParsedIntoFakeDecisions() {
        let summary = "Launch stays on track. Two blockers remain."
        #expect(OverviewPreview.snippet(summary) == summary)
        #expect(OverviewPreview.snippet(summary)?.contains("Key Decisions") != true)
    }
}

@Suite struct OverviewPresentationTests {
    private let actionsJSON = ActionItem.encodeList([
        ActionItem(text: "Ship Friday", owner: nil, done: false)
    ])

    @Test func emptyAndWhitespaceFieldsAreNotReadableContent() {
        #expect(
            !OverviewPresentation.hasReadableContent(
                summary: nil,
                notesMarkdown: "",
                enhancedNotesMarkdown: nil,
                actionItemsJSON: nil))
        #expect(
            !OverviewPresentation.hasReadableContent(
                summary: "  \n  ",
                notesMarkdown: "   ",
                enhancedNotesMarkdown: "\n",
                actionItemsJSON: "[]"))
    }

    @Test func summaryNotesActionsAndAINotesCountAsReadable() {
        #expect(
            OverviewPresentation.hasReadableContent(
                summary: "Launch stays on track.",
                notesMarkdown: "",
                enhancedNotesMarkdown: nil,
                actionItemsJSON: nil))
        #expect(
            OverviewPresentation.hasReadableContent(
                summary: nil,
                notesMarkdown: "raw scratch notes",
                enhancedNotesMarkdown: nil,
                actionItemsJSON: nil))
        #expect(
            OverviewPresentation.hasReadableContent(
                summary: nil,
                notesMarkdown: "",
                enhancedNotesMarkdown: "## Decisions\n- keep the date",
                actionItemsJSON: nil))
        #expect(
            OverviewPresentation.hasReadableContent(
                summary: nil,
                notesMarkdown: "",
                enhancedNotesMarkdown: nil,
                actionItemsJSON: actionsJSON))
    }

    @Test func idleAlwaysShowsContentWithoutProgress() {
        #expect(
            OverviewPresentation.layout(
                isEnhancing: false, isProcessing: false, hasReadableContent: false)
                == .content(progress: nil))
        #expect(
            OverviewPresentation.layout(
                isEnhancing: false, isProcessing: false, hasReadableContent: true)
                == .content(progress: nil))
    }

    @Test func emptyBusyUsesFullProgressAndNeverReady() {
        #expect(
            OverviewPresentation.layout(
                isEnhancing: true, isProcessing: false, hasReadableContent: false)
                == .fullProgress(.enhancing))
        #expect(
            OverviewPresentation.layout(
                isEnhancing: false, isProcessing: true, hasReadableContent: false)
                == .fullProgress(.processing))
        #expect(OverviewPresentation.Busy.enhancing.title == "Writing notes…")
        #expect(OverviewPresentation.Busy.processing.title == "Processing this recording…")
        #expect(
            !OverviewPresentation.Busy.enhancing.title.localizedCaseInsensitiveContains("ready"))
        #expect(
            !OverviewPresentation.Busy.processing.title.localizedCaseInsensitiveContains("ready"))
        #expect(
            !OverviewPresentation.Busy.enhancing.detail.localizedCaseInsensitiveContains("ready"))
        #expect(
            !OverviewPresentation.Busy.processing.detail.localizedCaseInsensitiveContains("ready"))
    }

    @Test func populatedReEnhanceKeepsContentWithEnhancingProgress() {
        #expect(
            OverviewPresentation.layout(
                isEnhancing: true, isProcessing: true, hasReadableContent: true)
                == .content(progress: .enhancing))
    }

    @Test func rawNotesDuringPostStopKeepContentWithProcessingProgress() {
        #expect(
            OverviewPresentation.layout(
                isEnhancing: false, isProcessing: true, hasReadableContent: true)
                == .content(progress: .processing))
    }

    @Test func enhanceStaysDisabledWhileBusy() {
        #expect(
            !OverviewPresentation.enhanceDisabled(
                isEnhancing: false, isProcessing: false, isRecordingThisMeeting: false))
        #expect(
            OverviewPresentation.enhanceDisabled(
                isEnhancing: true, isProcessing: false, isRecordingThisMeeting: false))
        #expect(
            OverviewPresentation.enhanceDisabled(
                isEnhancing: false, isProcessing: true, isRecordingThisMeeting: false))
        #expect(
            OverviewPresentation.enhanceDisabled(
                isEnhancing: false, isProcessing: false, isRecordingThisMeeting: true))
    }
}

@Suite struct TranscriptSourceTests {
    @Test func channelLabelsAreMicAndSystem() {
        #expect(TranscriptSource.label(.mic) == "Mic")
        #expect(TranscriptSource.label(.system) == "System")
    }
}

@Suite @MainActor struct MeetingDetailInitialTabTests {
    @Test func normalEntryLandsOnOverviewWhetherOrNotAudioExists() {
        // Covers completed meetings with mic+system audio, mic-only audio,
        // and no audio at all: all used to divert to Transcript or Notes.
        #expect(MeetingDetailView.initialTab(preferNotes: false) == .overview)
    }

    @Test func notesLibraryRouteStillLandsOnNotes() {
        #expect(MeetingDetailView.initialTab(preferNotes: true) == .notes)
    }
}

@Suite @MainActor struct MeetingTranscriptModelTests {
    private func seg(_ text: String) -> TranscriptSegment {
        TranscriptSegment.new(
            meetingID: "m", channel: .system, speaker: "Them",
            text: text, startSeconds: 0, endSeconds: 1, isFinal: true)
    }

    /// transcriptSegment has a foreign key on meeting, so rows used as
    /// cross-meeting noise need a real parent.
    private func saveNoiseMeeting(in db: AppDatabase) throws -> String {
        var noise = Meeting.new(title: "Noise", language: "en-US")
        noise.id = "noise-\(UUID().uuidString)"
        try db.save(noise)
        return noise.id
    }

    private func waitUntil(
        _ condition: () -> Bool, _ what: String
    ) async throws {
        for _ in 0..<400 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("timed out waiting for \(what), phase stayed unresolved")
    }

    @Test func loadsRealSegmentsThroughTheRealDatabase() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "Real path", language: "en-US")
        try db.save(meeting)
        try db.save(
            TranscriptSegment.new(
                meetingID: meeting.id, channel: .system, speaker: "Them",
                text: "first line", startSeconds: 0, endSeconds: 1, isFinal: true))
        try db.save(
            TranscriptSegment.new(
                meetingID: meeting.id, channel: .mic, speaker: "Me",
                text: "second line", startSeconds: 1, endSeconds: 2, isFinal: true))
        // A row for a different meeting must not leak into this meeting.
        var noise = seg("other meeting")
        noise.meetingID = try saveNoiseMeeting(in: db)
        try db.save(noise)

        let model = MeetingTranscriptModel()
        let meetingID = meeting.id
        model.reload {
            try await Task.detached(priority: .userInitiated) {
                try db.fetchSegments(meetingID: meetingID)
            }.value
        }
        #expect(model.phase == .loading)
        try await waitUntil(
            { model.phase == .loaded && model.segments.count == 2 }, "both segments")
        #expect(model.segments.map(\.text) == ["first line", "second line"])
    }

    @Test func databaseFailureIsSurfacedInsteadOfSwallowedAsEmpty() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        try await db.writer.write { try $0.drop(table: "transcriptSegment") }

        let model = MeetingTranscriptModel()
        model.reload {
            try await Task.detached(priority: .userInitiated) {
                try db.fetchSegments(meetingID: "any")
            }.value
        }
        try await waitUntil(
            {
                if case .failed = model.phase { return true }
                return false
            }, "a failed phase")
        guard case .failed(let message) = model.phase else { return }
        #expect(!message.isEmpty)
        #expect(model.segments.isEmpty)
    }

    @Test func retryAfterFailureReloadsFreshData() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "Retry", language: "en-US")
        try db.save(meeting)
        try await db.writer.write { try $0.drop(table: "transcriptSegment") }

        let model = MeetingTranscriptModel()
        let meetingID = meeting.id
        model.reload {
            try await Task.detached(priority: .userInitiated) {
                try db.fetchSegments(meetingID: meetingID)
            }.value
        }
        try await waitUntil(
            {
                if case .failed = model.phase { return true }
                return false
            }, "a failed phase")

        // Retry against a healthy database whose table exists.
        let fresh = try AppDatabase(writer: DatabaseQueue())
        let parent = Meeting.new(title: "Fresh parent", language: "en-US")
        try fresh.save(parent)
        var row = seg("after retry")
        row.meetingID = parent.id
        try fresh.save(row)
        let parentID = parent.id
        model.reload {
            try await Task.detached(priority: .userInitiated) {
                try fresh.fetchSegments(meetingID: parentID)
            }.value
        }
        try await waitUntil(
            { model.phase == .loaded && model.segments.count == 1 }, "the reloaded row")
        #expect(model.segments.map(\.text) == ["after retry"])
    }

    @Test func emptyResultIsLoadedEmptyNotAFailure() async throws {
        let model = MeetingTranscriptModel()
        model.reload { [] }
        try await waitUntil({ model.phase == .loaded }, "an empty load")
        #expect(model.segments.isEmpty)
    }

    @Test func staleCompletionDoesNotClobberTheNewestLoad() async throws {
        let model = MeetingTranscriptModel()
        let slow = seg("slow stale row")
        let fast = seg("fast fresh row")
        model.reload {
            try await Task.sleep(for: .milliseconds(150))
            return [slow]
        }
        model.reload { [fast] }
        try await waitUntil(
            { model.phase == .loaded && model.segments == [fast] }, "the fast load")
        // The slow load lands after the fast one and must be ignored.
        try await Task.sleep(for: .milliseconds(400))
        #expect(model.segments == [fast])
    }
}

@Suite struct PlaybackTransportTests {
    @Test func progressClampsAndRejectsNonFiniteDuration() {
        #expect(PlaybackTransport.progress(current: 5, duration: 10) == 0.5)
        #expect(PlaybackTransport.progress(current: -1, duration: 10) == 0)
        #expect(PlaybackTransport.progress(current: 40, duration: 10) == 1)
        #expect(PlaybackTransport.progress(current: 1, duration: 0) == 0)
        #expect(PlaybackTransport.progress(current: .nan, duration: 10) == 0)
        #expect(PlaybackTransport.progress(current: 1, duration: .infinity) == 0)
    }

    @Test func ringIsLargerThanTheOldFilledBlobButNotHuge() {
        #expect(PlaybackTransport.ringSize == 44)
        #expect(PlaybackTransport.innerSize == 28)
        #expect(PlaybackTransport.ringSize > 32)
        #expect(PlaybackTransport.ringSize < 64)
    }
}

@Suite struct LiveNotesAnchorTests {
    @Test func quickNoteStillScrollsToTheSameCard() {
        #expect(LiveNotesAnchor.cardID == "live-notes-card")
    }
}

@Suite @MainActor struct EnhancedNotesDocumentTests {
    private func hugeMarkdown(lines: Int) -> String {
        "## Decisions\n- Launch moved to July\n"
            + String(repeating: "- filler line for the notes budget\n", count: lines)
    }

    private func waitUntilComplete(_ document: EnhancedNotesDocument) async throws {
        for _ in 0..<400 {
            if document.isComplete { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("timed out waiting for the full parse")
    }

    @Test func longContentShowsABoundedPrefixImmediatelyAndCompletesLater() async throws {
        let source = hugeMarkdown(lines: 50_000)
        let document = EnhancedNotesDocument()
        document.update(source: source)
        #expect(!document.isComplete)
        #expect(document.blocks.count == EnhancedNotesDocument.previewBlockLimit)
        try await waitUntilComplete(document)
        #expect(document.blocks == MarkdownParser.parse(source))
        #expect(document.blocks.count > EnhancedNotesDocument.previewBlockLimit)
    }

    @Test func enteringALongDocumentCostsAFractionOfTheFullParse() {
        let source = hugeMarkdown(lines: 20_000)
        let clock = ContinuousClock()
        func nanos(_ body: () -> Int) -> Int64 {
            (0..<3).map { _ in
                let duration = clock.measure { _ = body() }
                let parts = duration.components
                return parts.seconds * 1_000_000_000 + parts.attoseconds / 1_000_000_000
            }.min() ?? Int64.max
        }
        let entryNs = nanos {
            let document = EnhancedNotesDocument()
            document.update(source: source)
            return document.blocks.count
        }
        var fullBlocks = 0
        let fullNs = nanos {
            fullBlocks = MarkdownParser.parse(source).count
            return fullBlocks
        }
        #expect(fullBlocks > EnhancedNotesDocument.previewBlockLimit)
        #expect(
            entryNs * 8 < fullNs,
            "entry \(entryNs)ns vs full parse \(fullNs)ns over \(fullBlocks) blocks")
    }

    @Test func shortContentCompletesImmediatelyWithoutBackgroundWork() {
        let document = EnhancedNotesDocument()
        document.update(source: "## Decisions\n- one")
        #expect(document.isComplete)
        #expect(document.blocks.count == 2)
    }

    @Test func emptySourceIsCompleteAndEmpty() {
        let document = EnhancedNotesDocument()
        document.update(source: "")
        #expect(document.isComplete)
        #expect(document.blocks.isEmpty)
    }

    @Test func reentryWithTheSameSourceKeepsTheCompletedCache() async throws {
        let source = hugeMarkdown(lines: 20_000)
        let document = EnhancedNotesDocument()
        document.update(source: source)
        try await waitUntilComplete(document)
        let fullCount = document.blocks.count
        document.update(source: source)
        #expect(document.isComplete)
        #expect(document.blocks.count == fullCount)
    }

    @Test func sourceChangeInvalidatesAndStaleResultsNeverLand() async throws {
        let old = hugeMarkdown(lines: 100_000)
        let new = "## Fresh\n- new content"
        let document = EnhancedNotesDocument()
        document.update(source: old)
        document.update(source: new)
        #expect(document.blocks == MarkdownParser.parse(new))
        try await waitUntilComplete(document)
        #expect(document.blocks == MarkdownParser.parse(new))
        #expect(document.blocks != MarkdownParser.parse(old))
        try await Task.sleep(for: .milliseconds(300))
        #expect(document.blocks == MarkdownParser.parse(new))
    }
}
