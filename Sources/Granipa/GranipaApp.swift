import SwiftUI

@main
struct GranipaApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Grañipa") {
            MainWindow()
                .environment(appState)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 720)

        MenuBarExtra(
            "Grañipa",
            systemImage: appState.recorder.isRecording ? "record.circle.fill" : "waveform"
        ) {
            MenuBarView()
                .environment(appState)
        }

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
        }
    }
}
