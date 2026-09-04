import Foundation
import Testing

@testable import Granipa

/// Contract: Muse touches meeting system audio only when the user picked the
/// engine AND a key exists. Everything else — unset, empty, local, keyless —
/// stays on the Apple engine.
@Suite struct MeetingASRPolicyTests {
    @Test func museRequiresExplicitEngineAndKey() {
        #expect(MeetingASRPolicy.usesMuseForSystem(engine: "muse", hasMuseKey: true))
    }

    @Test func everythingElseStaysLocal() {
        #expect(!MeetingASRPolicy.usesMuseForSystem(engine: nil, hasMuseKey: true))
        #expect(!MeetingASRPolicy.usesMuseForSystem(engine: "", hasMuseKey: true))
        #expect(!MeetingASRPolicy.usesMuseForSystem(engine: "muse", hasMuseKey: false))
        #expect(!MeetingASRPolicy.usesMuseForSystem(engine: "local", hasMuseKey: true))
    }

    @Test func liveASRIsOffUnlessExplicitlyEnabled() {
        #expect(!MeetingASRPolicy.usesLiveASR(flag: nil))
        #expect(!MeetingASRPolicy.usesLiveASR(flag: false))
        #expect(MeetingASRPolicy.usesLiveASR(flag: true))
    }

    @Test func liveCaptionsNeedLiveASRAndTheCaptionsPref() {
        #expect(!MeetingASRPolicy.usesLiveCaptions(live: nil, captions: true))
        #expect(!MeetingASRPolicy.usesLiveCaptions(live: false, captions: true))
        #expect(!MeetingASRPolicy.usesLiveCaptions(live: true, captions: false))
        #expect(!MeetingASRPolicy.usesLiveCaptions(live: nil, captions: nil))
        #expect(MeetingASRPolicy.usesLiveCaptions(live: true, captions: true))
        #expect(MeetingASRPolicy.usesLiveCaptions(live: true, captions: nil))
    }

    @Test func dictationRestoreDoesNotShowEmptyCaptionsWhenLiveASRIsOff() {
        #expect(
            !MeetingASRPolicy.shouldShowCaptionsOverlay(
                requested: true, dismissed: false, hasLiveCoordinator: true,
                live: false, captions: true))
        #expect(
            !MeetingASRPolicy.shouldShowCaptionsOverlay(
                requested: true, dismissed: false, hasLiveCoordinator: true,
                live: nil, captions: true))
    }

    @Test func captionsStayHiddenWithoutALiveCoordinator() {
        #expect(
            !MeetingASRPolicy.shouldShowCaptionsOverlay(
                requested: true, dismissed: false, hasLiveCoordinator: false,
                live: true, captions: true))
    }

    @Test func captionsShowOnlyWithLiveASRCoordinatorAndPref() {
        #expect(
            MeetingASRPolicy.shouldShowCaptionsOverlay(
                requested: true, dismissed: false, hasLiveCoordinator: true,
                live: true, captions: true))
        #expect(
            MeetingASRPolicy.shouldShowCaptionsOverlay(
                requested: true, dismissed: false, hasLiveCoordinator: true,
                live: true, captions: nil))
        #expect(
            !MeetingASRPolicy.shouldShowCaptionsOverlay(
                requested: false, dismissed: false, hasLiveCoordinator: true,
                live: true, captions: true))
        #expect(
            !MeetingASRPolicy.shouldShowCaptionsOverlay(
                requested: true, dismissed: true, hasLiveCoordinator: true,
                live: true, captions: true))
        #expect(
            !MeetingASRPolicy.shouldShowCaptionsOverlay(
                requested: true, dismissed: false, hasLiveCoordinator: true,
                live: true, captions: false))
    }

    /// SettingsView is a private SwiftUI form; `@AppStorage` only writes when a
    /// rendered binding mutates, and this suite has no view host. Same
    /// source-contract pattern as BatteryHelperTests (read the repo file).
    @Test func settingsWritesTheLiveASRKeyPolicyReads() throws {
        let settings = try granipaSource("Sources/Granipa/UI/SettingsView.swift")
        let policy = try granipaSource(
            "Sources/Granipa/Transcription/MeetingASRPolicy.swift")
        let menu = try granipaSource("Sources/Granipa/UI/MenuBarView.swift")

        #expect(policy.contains(#"forKey: "liveMeetingASR""#))
        #expect(policy.contains(#"forKey: "meetingCaptionsEnabled""#))
        #expect(appStorageFlag(in: settings, key: "liveMeetingASR") == false)
        #expect(appStorageFlag(in: settings, key: "meetingCaptionsEnabled") == true)
        #expect(menu.contains("MeetingASRPolicy.usesLiveCaptions()"))
        if let gate = menu.range(of: "MeetingASRPolicy.usesLiveCaptions()"),
            let show = menu.range(of: "Show Captions"),
            let hide = menu.range(of: "Hide Captions")
        {
            #expect(gate.lowerBound < show.lowerBound)
            #expect(gate.lowerBound < hide.lowerBound)
        }
    }

    /// Overlay setVisible used to honor only meetingCaptionsEnabled, so
    /// dictation restore could raise an empty panel while live ASR was off.
    /// Menu advertised Show/Hide Captions from prefs even when this recording
    /// never started a coordinator.
    @Test func overlayAndMenuKeepLiveCaptionsCoherent() throws {
        let overlay = try granipaSource("Sources/Granipa/UI/CaptionsOverlayController.swift")
        let menu = try granipaSource("Sources/Granipa/UI/MenuBarView.swift")
        let dictation = try granipaSource("Sources/Granipa/Dictation/DictationController.swift")
        let settings = try granipaSource("Sources/Granipa/UI/SettingsView.swift")

        #expect(overlay.contains("MeetingASRPolicy.shouldShowCaptionsOverlay"))
        #expect(overlay.contains("appState?.transcription"))
        #expect(!overlay.contains(#"forKey: "meetingCaptionsEnabled""#))

        #expect(menu.contains("app.transcription"))
        if let coordinator = menu.range(of: "app.transcription"),
            let show = menu.range(of: "Show Captions"),
            let hide = menu.range(of: "Hide Captions")
        {
            #expect(coordinator.lowerBound < show.lowerBound)
            #expect(coordinator.lowerBound < hide.lowerBound)
        }

        #expect(dictation.contains("setVisible(meetingIsRecording)"))
        #expect(settings.contains("onChange(of: liveMeetingASR)"))
        #expect(settings.contains("onChange(of: meetingCaptions)"))
        #expect(settings.contains("CaptionsOverlayController.shared.setVisible"))
        if let liveToggle = settings.range(of: #"@AppStorage("liveMeetingASR")"#),
            let captionsToggle = settings.range(of: #"@AppStorage("meetingCaptionsEnabled")"#),
            let sync = settings.range(of: "CaptionsOverlayController.shared.setVisible")
        {
            #expect(liveToggle.lowerBound < sync.lowerBound)
            #expect(captionsToggle.lowerBound < sync.lowerBound)
        }
    }
}

private func granipaSource(_ relativePath: String) throws -> String {
    let testsFile = URL(fileURLWithPath: #filePath)
    let repo = testsFile.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repo.appendingPathComponent(relativePath), encoding: .utf8)
}

private func appStorageFlag(in source: String, key: String) -> Bool? {
    guard let start = source.range(of: #"@AppStorage("\#(key)")"#) else {
        return nil
    }
    let window = source[start.upperBound...].prefix(160)
    if window.contains("= false") { return false }
    if window.contains("= true") { return true }
    return nil
}
