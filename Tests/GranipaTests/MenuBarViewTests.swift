import Foundation
import Testing

@testable import Granipa

@Suite struct MenuBarViewTests {
    @Test func statusMappingPrefersCaptureOverNotesProcessing() {
        #expect(
            MenuBarStatus.resolve(
                recorderBusy: true, dictationActive: true, processingNotes: true)
                == .recording)
        #expect(
            MenuBarStatus.resolve(
                recorderBusy: false, dictationActive: true, processingNotes: true)
                == .dictating)
        #expect(
            MenuBarStatus.resolve(
                recorderBusy: false, dictationActive: false, processingNotes: true)
                == .processing)
        #expect(
            MenuBarStatus.resolve(
                recorderBusy: false, dictationActive: false, processingNotes: false)
                == .idle)
        #expect(MenuBarStatus.idle.symbolName == "waveform")
        #expect(MenuBarStatus.idle.accessibilityLabel == "Grañipa")
        #expect(MenuBarStatus.dictating.symbolName == "mic.fill")
        #expect(MenuBarStatus.dictating.accessibilityLabel == "Dictating")
        #expect(MenuBarStatus.recording.symbolName == "record.circle.fill")
        #expect(MenuBarStatus.recording.accessibilityLabel == "Recording")
        #expect(MenuBarStatus.processing.symbolName == "ellipsis.circle.fill")
        #expect(MenuBarStatus.processing.accessibilityLabel == "Processing notes")
    }

    @Test func batteryHeadlineDoesNotDuplicatePercent() {
        #expect(
            BatteryMenuHeadline.text(
                for: BatterySnapshot(
                    isPresent: true, percent: 80, isCharging: true, minutesToEmpty: nil))
                == "80% charging")
        #expect(
            BatteryMenuHeadline.text(
                for: BatterySnapshot(
                    isPresent: true, percent: 80, isCharging: false, minutesToEmpty: 80))
                == "80% · 1h 20m")
        #expect(
            BatteryMenuHeadline.text(
                for: BatterySnapshot(
                    isPresent: true, percent: 80, isCharging: false, minutesToEmpty: 20))
                == "80% · 20m")
        #expect(
            BatteryMenuHeadline.text(
                for: BatterySnapshot(
                    isPresent: true, percent: 80, isCharging: false, minutesToEmpty: nil))
                == "80%")
        #expect(
            BatteryMenuHeadline.text(
                for: BatterySnapshot(
                    isPresent: true, percent: 80, isCharging: true, minutesToEmpty: 40))
                == "80% charging")
    }

    @Test func captureToolsAndAppKeepExistingCallers() throws {
        let menu = try granipaSource("Sources/Granipa/UI/MenuBarView.swift")
        let app = try granipaSource("Sources/Granipa/GranipaApp.swift")

        #expect(menu.contains("toggleFromMenu()"))
        #expect(menu.contains("stopRecording()"))
        #expect(menu.contains("startRecording()"))
        #expect(menu.contains("createMeeting()"))
        #expect(menu.contains(#"openWindow(id: "recording-hud")"#))
        #expect(menu.contains("ClipboardPanelController.shared.toggle()"))
        #expect(menu.contains("OCRService.captureAndCopy()"))
        #expect(menu.contains("EmojiPalette.show()"))
        #expect(menu.contains("DictationHistoryPanelController.shared.toggle()"))
        #expect(menu.contains(#"openWindow(id: "main")"#))
        #expect(menu.contains(#"openWindow(id: "onboarding")"#))
        #expect(menu.contains("UpdaterManager.shared.checkForUpdates()"))
        #expect(menu.contains("UpdaterManager.shared.isAvailable"))
        #expect(menu.contains("NSApp.terminate(nil)"))
        #expect(menu.contains("MeetingASRPolicy.usesLiveCaptions()"))
        #expect(menu.contains("app.transcription"))
        #expect(menu.contains("Show Captions"))
        #expect(menu.contains("Hide Captions"))
        #expect(menu.contains(".keyboardShortcut(\"v\", modifiers: [.option, .shift])"))
        #expect(menu.contains(".keyboardShortcut(\"t\", modifiers: [.option, .shift])"))
        #expect(menu.contains(".keyboardShortcut(\"e\", modifiers: [.option, .shift])"))
        #expect(menu.contains(".keyboardShortcut(\"h\", modifiers: [.option, .shift])"))
        #expect(menu.contains("Quick note"))
        #expect(menu.contains("sidebarDestination = .settings"))
        #expect(menu.contains("Setup Guide…"))
        #expect(menu.contains("Quit Grañipa"))
        #expect(app.contains(".menuBarExtraStyle(.menu)"))
    }

    @Test func liveStatesAreTruthfulAndNeverDummyButtons() throws {
        let menu = try granipaSource("Sources/Granipa/UI/MenuBarView.swift")
        #expect(menu.contains("case .preparing, .listening"))
        #expect(menu.contains("case .processing"))
        #expect(menu.contains("Transcribing…"))
        #expect(menu.contains("Processing notes…"))
        #expect(menu.contains("Transcription failed"))
        #expect(menu.contains(".disabled(app.recorder.isBusy)"))
        #expect(menu.contains("processingMeetingID"))
        #expect(menu.contains("enhancingMeetingIDs"))
        #expect(!menu.contains("livePipeline"))
        #expect(!menu.contains(#"Button("\(phase.label) notes…")"#))
        #expect(!menu.contains(".disabled(true)"))
        #expect(!menu.contains("if app.dictation.phase.isActive"))
        #expect(!menu.contains(#"Button("New Meeting")"#))
    }

    @Test func batteryIsNestedAndPercentLineUsesExistingFields() throws {
        let menu = try granipaSource("Sources/Granipa/UI/MenuBarView.swift")
        #expect(menu.contains("snapshot.isPresent"))
        #expect(menu.contains("Menu(\"Battery\")") || menu.contains("Menu {"))
        #expect(menu.contains("BatteryMenuSection"))
        #expect(menu.contains("limiterEnabled"))
        #expect(menu.contains("beginDischarge()"))
        #expect(menu.contains("beginTopUp()"))
        #expect(menu.contains("heatProtection"))
        #expect(menu.contains("startCalibration()"))
        #expect(menu.contains("stopCalibration()"))
        #expect(menu.contains("magSafeLED"))
        #expect(menu.contains("installHelper()"))
        #expect(menu.contains("controlMessage"))
        #expect(menu.contains("BatteryMenuHeadline.text(for:"))
        #expect(!menu.contains(#"Text("\(snap.percent)% · \(snap.menuBarText)")"#))
        if let present = menu.range(of: "snapshot.isPresent"),
            let nested = menu.range(of: "BatteryMenuSection")
        {
            #expect(present.lowerBound < nested.lowerBound)
        }
    }

    @Test func extraAddsNoTimersAndLabelHasNoBattery() throws {
        let menu = try granipaSource("Sources/Granipa/UI/MenuBarView.swift")
        let app = try granipaSource("Sources/Granipa/GranipaApp.swift")
        for source in [menu, app] {
            #expect(!source.contains("TimelineView"))
            #expect(!source.contains("Timer.publish"))
            #expect(!source.contains("Task.sleep"))
        }
        let labelStart = app.range(of: "enum MenuBarStatus") ?? app.range(of: "struct MenuBarLabel")
        let labelSource = labelStart.map { String(app[$0.lowerBound...]) } ?? menu
        #expect(!labelSource.contains("BatteryService"))
        #expect(!labelSource.contains("menuBarText"))
        #expect(labelSource.contains("accessibilityLabel"))
        #expect(labelSource.contains("processingMeetingID"))
        #expect(!labelSource.contains("meetings.contains"))
    }

    /// NEW: Settings must be an embedded main-window destination, not a popup
    /// Settings scene / SettingsLink. Observed red against 99e7703 (SettingsLink
    /// in the menu bar, `Settings {` in GranipaApp, `openSettings()` in MainWindow).
    @Test func settingsOpensEmbeddedInTheMainWindowNotAPopupScene() throws {
        let menu = try granipaSource("Sources/Granipa/UI/MenuBarView.swift")
        let app = try granipaSource("Sources/Granipa/GranipaApp.swift")
        let main = try granipaSource("Sources/Granipa/UI/MainWindow.swift")
        let sidebar = try granipaSource("Sources/Granipa/UI/SidebarView.swift")

        #expect(!menu.contains("SettingsLink"))
        #expect(!sidebar.contains("SettingsLink"))
        #expect(!main.contains("openSettings()"))
        #expect(!main.contains("@Environment(\\.openSettings)"))
        #expect(!app.contains("Settings {"))
        #expect(menu.contains("sidebarDestination = .settings"))
        #expect(menu.contains(#"openWindow(id: "main")"#))
        #expect(sidebar.contains("sidebarDestination = .settings"))
        #expect(app.contains("CommandGroup(replacing: .appSettings)"))
        #expect(app.contains(".keyboardShortcut(\",\", modifiers: .command)"))
    }
}

private func granipaSource(_ relativePath: String) throws -> String {
    let testsFile = URL(fileURLWithPath: #filePath)
    let repo = testsFile.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repo.appendingPathComponent(relativePath), encoding: .utf8)
}
