import Foundation
import Testing

@testable import Granipa

/// The Dictation page's header owns dictation capture, not meeting recording.
/// Routing is asserted on source the same way MenuBarViewTests pins the menu's
/// wiring: the page is a thin SwiftUI surface, its contract is what it calls.
@Suite struct DictationPageHeaderTests {
    @Test func pageRoutesRecordToDictationEngineNotMeetingRecorder() throws {
        let page = try granipaSource("Sources/Granipa/Dictation/DictationHistoryView.swift")
        #expect(page.contains("DictationDestinationHeader(dictation: app.dictation)"))
        #expect(!page.contains("startRecording()"))
        #expect(!page.contains(#"DestinationHeader(title: "Dictation")"#))
    }

    @Test func headerGuardsMicConflictAndKeepsQuickNote() throws {
        let chrome = try granipaSource("Sources/Granipa/Dictation/DictationLibraryChrome.swift")
        #expect(chrome.contains("toggleFromMenu()"))
        #expect(chrome.contains("app.recorder.isBusy"))
        #expect(chrome.contains("createMeeting()"))
        #expect(!chrome.contains("startRecording()"))
    }

    @Test func headerActionMirrorsMenuBarCaptureStates() {
        func resolve(_ phase: DictationPhase, busy: Bool = false) -> DictationHeaderAction {
            DictationHeaderAction.resolve(phase: phase, recorderBusy: busy)
        }

        #expect(resolve(.idle) == .record(disabled: false))
        #expect(resolve(.done) == .record(disabled: false))
        #expect(resolve(.failed("boom")) == .record(disabled: false))
        #expect(resolve(.idle, busy: true) == .record(disabled: true))
        #expect(resolve(.preparing) == .stop)
        #expect(resolve(.listening) == .stop)
        #expect(resolve(.processing) == .transcribing)
    }

    @Test func headerActionLabelsAndEnablementAreTruthful() {
        #expect(DictationHeaderAction.record(disabled: false).title == "Record")
        #expect(DictationHeaderAction.stop.title == "Stop")
        #expect(DictationHeaderAction.transcribing.title == "Transcribing…")
        #expect(DictationHeaderAction.record(disabled: false).isEnabled)
        #expect(!DictationHeaderAction.record(disabled: true).isEnabled)
        #expect(DictationHeaderAction.stop.isEnabled)
        #expect(!DictationHeaderAction.transcribing.isEnabled)
        #expect(DictationHeaderAction.record(disabled: false).systemImage == "record.circle")
        #expect(DictationHeaderAction.stop.systemImage == "stop.circle.fill")
    }
}

private func granipaSource(_ relativePath: String) throws -> String {
    let testsFile = URL(fileURLWithPath: #filePath)
    let repo = testsFile.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repo.appendingPathComponent(relativePath), encoding: .utf8)
}
