import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var app = app
        VStack(spacing: 0) {
            if let appName = app.detector.detectedApp, !app.recorder.isRecording {
                HStack {
                    Label("Looks like \(appName) is in a call.", systemImage: "video.fill")
                    Spacer()
                    Button("Record") {
                        app.startRecordingFromDetection()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Dismiss") {
                        app.detector.dismiss()
                    }
                }
                .padding(10)
                .background(.yellow.opacity(0.15))
            }
            splitView
        }
        .onChange(of: app.recorder.isRecording) {
            if app.recorder.isRecording {
                openWindow(id: "recording-hud")
            } else {
                dismissWindow(id: "recording-hud")
            }
        }
    }

    private var splitView: some View {
        @Bindable var app = app
        return NavigationSplitView {
            MeetingListView(selection: $app.selectedMeetingID)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280)
        } detail: {
            if let meeting = app.selectedMeeting {
                MeetingDetailView(meeting: meeting)
                    .id(meeting.id)
            } else {
                ContentUnavailableView(
                    "No meeting selected",
                    systemImage: "waveform",
                    description: Text("Select a meeting from the list or create a new one.")
                )
            }
        }
        .alert("Error", isPresented: .constant(app.loadError != nil)) {
            Button("OK") { app.loadError = nil }
        } message: {
            Text(app.loadError ?? "")
        }
    }
}
