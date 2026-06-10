import SwiftUI

@main
struct GranipaApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup("Grañipa") {
            MainWindow()
                .environment(appState)
        }

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
        .windowLevel(.floating)
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}
