import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Grañipa") {
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        if app.recorder.isRecording {
            Button("Stop Recording") {
                Task { await app.stopRecording() }
            }
        } else {
            Button("Record New Meeting") {
                app.startRecording()
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        Button("New Meeting") {
            app.createMeeting()
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Quit Grañipa") {
            NSApp.terminate(nil)
        }
    }
}
