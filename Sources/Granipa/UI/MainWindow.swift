import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var app = app
        NavigationSplitView {
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
