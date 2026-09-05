import os
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let lifecycleLog = OSLog(
        subsystem: "com.zertyn.granipa", category: "lifecycle")

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if V2FixtureRuntime.isActive {
            os_signpost(.event, log: Self.lifecycleLog, name: "appReady")
            return
        }
        #endif
        AppRelocator.offerMoveIfNeeded()
        os_signpost(.event, log: Self.lifecycleLog, name: "appReady")
    }

    func applicationWillTerminate(_ notification: Notification) {
        #if DEBUG
        if V2FixtureRuntime.isActive { return }
        #endif
        BatteryService.shared.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        #if DEBUG
        if V2FixtureRuntime.isActive { return }
        #endif
        BatteryHelperClient.shared.invalidateStatusCache()
    }
}

@main
struct GranipaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState: AppState

    init() {
        #if DEBUG
        switch V2FixtureRuntime.resolve(
            arguments: CommandLine.arguments,
            environment: ProcessInfo.processInfo.environment)
        {
        case .off:
            appState = AppState()
        case .run(let fixture):
            appState = AppState(fixture: fixture)
        case .refuse(let message):
            // Fail closed before any production database is opened.
            FileHandle.standardError.write(Data(("ERROR: \(message)\n").utf8))
            exit(1)
        }
        #else
        appState = AppState()
        #endif
    }

    var body: some Scene {
        WindowGroup("Grañipa", id: "main") {
            MainWindow()
                .environment(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: ShellLayout.defaultWindowWidth, height: 720)

        #if DEBUG
        MenuBarExtra(isInserted: .constant(!V2FixtureRuntime.isActive)) {
            if V2FixtureRuntime.isActive {
                EmptyView()
            } else {
                MenuBarView()
                    .environment(appState)
            }
        } label: {
            if V2FixtureRuntime.isActive {
                EmptyView()
            } else {
                MenuBarLabel(app: appState)
            }
        }
        .menuBarExtraStyle(.menu)
        #else
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarLabel(app: appState)
        }
        .menuBarExtraStyle(.menu)
        #endif

        Window("Welcome to Grañipa", id: "onboarding") {
            OnboardingView()
                .environment(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        Window("Recording", id: "recording-hud") {
            RecordingHUD()
                .environment(appState)
        }
        .windowStyle(.plain)
        .windowLevel(.floating)
        .windowResizability(.contentSize)
        .windowBackgroundDragBehavior(.enabled)
        .defaultPosition(.topTrailing)

        Settings {
            SettingsView()
                .environment(appState)
                .tint(Theme.accent)
        }
    }

}

enum MenuBarStatus: Equatable, Sendable {
    case idle
    case dictating
    case recording
    case processing

    var symbolName: String {
        switch self {
        case .idle: "waveform"
        case .dictating: "mic.fill"
        case .recording: "record.circle.fill"
        case .processing: "ellipsis.circle.fill"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle: "Grañipa"
        case .dictating: "Dictating"
        case .recording: "Recording"
        case .processing: "Processing notes"
        }
    }

    static func resolve(
        recorderBusy: Bool,
        dictationActive: Bool,
        processingNotes: Bool
    ) -> MenuBarStatus {
        if recorderBusy { return .recording }
        if dictationActive { return .dictating }
        if processingNotes { return .processing }
        return .idle
    }
}

private struct MenuBarLabel: View {
    var app: AppState

    var body: some View {
        let status = MenuBarStatus.resolve(
            recorderBusy: app.recorder.isBusy,
            dictationActive: app.dictation.phase.isActive,
            processingNotes: app.processingMeetingID != nil
                || !app.enhancingMeetingIDs.isEmpty)
        Image(systemName: status.symbolName)
            .accessibilityLabel(status.accessibilityLabel)
            .help(status.accessibilityLabel)
    }
}
