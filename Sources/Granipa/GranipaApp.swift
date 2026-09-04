import os
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let lifecycleLog = OSLog(
        subsystem: "com.zertyn.granipa", category: "lifecycle")

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppRelocator.offerMoveIfNeeded()
        os_signpost(.event, log: Self.lifecycleLog, name: "appReady")
    }

    func applicationWillTerminate(_ notification: Notification) {
        BatteryService.shared.stop()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
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

        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            MenuBarLabel(app: appState)
        }

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

private struct MenuBarLabel: View {
    var app: AppState

    var body: some View {
        Image(systemName: symbol)
    }

    private var symbol: String {
        if app.recorder.isRecording { return "record.circle.fill" }
        if app.dictation.phase.isActive { return "mic.fill" }
        if app.meetings.contains(where: { $0.status == .processing }) {
            return "ellipsis.circle.fill"
        }
        return "waveform"
    }
}
