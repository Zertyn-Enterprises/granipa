import Foundation
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

@Suite struct TranscriptSourceTests {
    @Test func channelLabelsAreMicAndSystem() {
        #expect(TranscriptSource.label(.mic) == "Mic")
        #expect(TranscriptSource.label(.system) == "System")
    }
}

@Suite struct MeetingDetailInitialTabTests {
    @Test func normalEntryLandsOnOverviewWhetherOrNotAudioExists() {
        // Covers completed meetings with mic+system audio, mic-only audio,
        // and no audio at all: all used to divert to Transcript or Notes.
        #expect(MeetingDetailView.initialTab(preferNotes: false) == .overview)
    }

    @Test func notesLibraryRouteStillLandsOnNotes() {
        #expect(MeetingDetailView.initialTab(preferNotes: true) == .notes)
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
