import SwiftUI

struct MeetingListView: View {
    @Environment(AppState.self) private var app
    @Binding var selection: String?
    @State private var searchQuery = ""
    @State private var searchResults: [Meeting] = []

    private var shownMeetings: [Meeting] {
        searchQuery.isEmpty ? app.meetings : searchResults
    }

    var body: some View {
        List(selection: $selection) {
            let upcoming = searchQuery.isEmpty ? app.calendar.upcoming.filter { $0.end > .now } : []
            if !upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(upcoming) { event in
                        UpcomingRow(event: event)
                    }
                }
            }
            Section(upcoming.isEmpty ? "" : "Meetings") {
                ForEach(shownMeetings) { meeting in
                    MeetingRow(meeting: meeting)
                        .tag(meeting.id)
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                app.deleteMeeting(id: meeting.id)
                            }
                        }
                }
            }
        }
        .navigationTitle("Meetings")
        .searchable(text: $searchQuery, placement: .sidebar, prompt: "Search notes & transcripts")
        .onChange(of: searchQuery) {
            guard !searchQuery.isEmpty, let db = app.database else {
                searchResults = []
                return
            }
            searchResults = (try? db.searchMeetings(query: searchQuery)) ?? []
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Meeting", systemImage: "plus") {
                    app.createMeeting()
                }
            }
        }
        .overlay {
            if shownMeetings.isEmpty {
                if searchQuery.isEmpty {
                    ContentUnavailableView(
                        "No meetings yet",
                        systemImage: "calendar.badge.plus",
                        description: Text("Your recorded meetings will appear here.")
                    )
                } else {
                    ContentUnavailableView.search(text: searchQuery)
                }
            }
        }
    }
}

private struct UpcomingRow: View {
    @Environment(AppState.self) private var app
    let event: CalendarMeeting

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline)
                    .lineLimit(1)
                Text(event.start, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let url = event.joinURL {
                Link(destination: url) {
                    Image(systemName: "video")
                }
                .help("Join meeting")
            }
            Button {
                app.startRecording(fromEvent: event)
            } label: {
                Image(systemName: "record.circle")
            }
            .buttonStyle(.borderless)
            .disabled(app.recorder.isRecording)
            .help("Record this meeting")
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
