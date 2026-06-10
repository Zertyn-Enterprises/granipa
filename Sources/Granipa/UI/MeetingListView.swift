import SwiftUI

struct MeetingListView: View {
    @Environment(AppState.self) private var app
    @Binding var selection: String?

    var body: some View {
        List(selection: $selection) {
            ForEach(app.meetings) { meeting in
                MeetingRow(meeting: meeting)
                    .tag(meeting.id)
                    .contextMenu {
                        Button("Delete", role: .destructive) {
                            app.deleteMeeting(id: meeting.id)
                        }
                    }
            }
        }
        .navigationTitle("Meetings")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Meeting", systemImage: "plus") {
                    app.createMeeting()
                }
            }
        }
        .overlay {
            if app.meetings.isEmpty {
                ContentUnavailableView(
                    "No meetings yet",
                    systemImage: "calendar.badge.plus",
                    description: Text("Your recorded meetings will appear here.")
                )
            }
        }
    }
}

private struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(meeting.title)
                .font(.headline)
                .lineLimit(1)
            HStack(spacing: 6) {
                if meeting.status == .recording {
                    Label("Recording", systemImage: "record.circle")
                        .foregroundStyle(.red)
                        .font(.caption)
                } else if meeting.status == .processing {
                    Label("Processing", systemImage: "gearshape.2")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else {
                    Text(meeting.createdAt, format: .dateTime.day().month().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
