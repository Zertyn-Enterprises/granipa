import Foundation
import Testing

@testable import Granipa

@Suite struct MeetingPermissionsStyleTests {
    @Test func playbackRecordUsesSharedPrimaryControl() throws {
        let source = try granipaSource("Sources/Granipa/UI/MeetingPlaybackBar.swift")
        #expect(source.contains("granipaPrimaryControl()"))
        #expect(!source.contains(".buttonStyle(.bordered)"))
        #expect(source.contains(".disabled(app.recorder.isBusy)"))
        #expect(source.contains("app.startRecording(meetingID: meeting.id)"))
        #expect(source.contains("frame(height: 44)"))
        #expect(source.contains("PlaybackTransport.ringSize"))
        #expect(PlaybackTransport.ringSize == 44)
        #expect(PlaybackTransport.innerSize == 28)
    }

    @Test func recordingBarRecordUsesSharedPrimaryAndStopStaysProminent() throws {
        let source = try granipaSource("Sources/Granipa/UI/RecordingBar.swift")
        #expect(source.contains("granipaPrimaryControl()"))
        #expect(source.contains(".buttonStyle(.borderedProminent)"))
        #expect(source.contains(".tint(Theme.statusListening)"))
        #expect(source.contains("app.startRecording(meetingID: meeting.id)"))
        #expect(source.contains("await app.stopRecording()"))
        #expect(!source.contains(".tint(Theme.accent)"))
    }

    @Test func overviewEnhanceRetryAndOpenNotesUseSharedSecondaryControl() throws {
        let source = try granipaSource("Sources/Granipa/UI/MeetingRecordedViews.swift")
        #expect(source.contains("granipaSecondaryControl()"))
        #expect(!source.contains(".buttonStyle(.bordered)"))
        #expect(source.contains("Button(\"Open notes\""))
        #expect(source.contains("Button(\"Retry\""))
        #expect(source.contains("Button(\"Try Again\""))
        #expect(source.contains("enhanceButton("))
        #expect(source.contains("OverviewPresentation.enhanceDisabled("))
    }

    @Test func permissionsRescanFixAndSystemSettingsUseSharedControls() throws {
        let source = try granipaSource("Sources/Granipa/UI/PermissionsView.swift")
        #expect(source.contains("granipaPrimaryControl()"))
        #expect(source.contains("granipaSecondaryControl()"))
        #expect(source.contains("Text(\"Fix recommended\")"))
        #expect(source.contains("Button(\"Open System Settings\")"))
        #expect(source.contains("Text(isRefreshing ? \"Checking\" : \"Rescan all\")"))
        #expect(source.contains(".buttonStyle(.borderedProminent)"))
        #expect(source.contains("button.buttonStyle(.bordered)"))
        #expect(source.contains("Task { await center.refresh() }"))
    }
}

private func granipaSource(_ relativePath: String) throws -> String {
    let testsFile = URL(fileURLWithPath: #filePath)
    let repo = testsFile.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repo.appendingPathComponent(relativePath), encoding: .utf8)
}
