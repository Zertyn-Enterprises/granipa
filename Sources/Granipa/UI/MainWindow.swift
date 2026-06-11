import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        @Bindable var app = app
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 248)
                .background(Theme.bgSidebar)

            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)

            VStack(spacing: 0) {
                if let appName = app.detector.detectedApp, !app.recorder.isRecording {
                    detectionBanner(appName: appName)
                }
                if let meeting = app.selectedMeeting {
                    MeetingDetailView(meeting: meeting)
                        .id(meeting.id)
                } else {
                    HomeView()
                }
            }
            .frame(maxWidth: .infinity)
            .background(Theme.bg)
        }
        .preferredColorScheme(.dark)
        .frame(minWidth: 960, minHeight: 600)
        .onChange(of: app.recorder.isRecording) {
            if app.recorder.isRecording {
                openWindow(id: "recording-hud")
            } else {
                dismissWindow(id: "recording-hud")
            }
        }
        .alert("Error", isPresented: .constant(app.loadError != nil)) {
            Button("OK") { app.loadError = nil }
        } message: {
            Text(app.loadError ?? "")
        }
    }

    private func detectionBanner(appName: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "video.fill")
                .foregroundStyle(Theme.accent)
            Text("Looks like \(appName) is in a call.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Record") {
                app.startRecordingFromDetection()
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            Button("Dismiss") {
                app.detector.dismiss()
            }
            .buttonStyle(.bordered)
            .tint(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.accent.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}
