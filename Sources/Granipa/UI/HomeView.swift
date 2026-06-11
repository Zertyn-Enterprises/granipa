import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var searchResults: [Meeting] = []

    private var isSearching: Bool { !app.searchQuery.isEmpty }

    private var activeFolder: Folder? {
        app.selectedFolderID.flatMap { id in app.folders.first { $0.id == id } }
    }

    private var shownMeetings: [Meeting] {
        let base = isSearching ? searchResults : app.meetings
        guard let folderID = app.selectedFolderID else { return base }
        return base.filter { $0.folderID == folderID }
    }

    private var headerTitle: String {
        if isSearching { return "Search" }
        if let folder = activeFolder { return folder.name }
        return nextEvent != nil ? "Coming up" : "Notes"
    }

    private var nextEvent: CalendarMeeting? {
        app.calendar.upcoming.first { $0.end > .now }
    }

    private var dayGroups: [(day: Date, meetings: [Meeting])] {
        let grouped = Dictionary(grouping: shownMeetings) {
            Calendar.current.startOfDay(for: $0.createdAt)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, meetings: $0.value.sorted { $0.createdAt > $1.createdAt }) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text(headerTitle)
                        .font(Theme.titleFont)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button {
                        app.createMeeting()
                    } label: {
                        Label("Quick note", systemImage: "plus")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }

                if !isSearching, activeFolder == nil, let event = nextEvent {
                    HeroEventCard(event: event)
                }

                if shownMeetings.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                } else {
                    ForEach(dayGroups, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(Theme.dayHeader(group.day))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.bottom, 2)
                            ForEach(group.meetings) { meeting in
                                HomeMeetingRow(meeting: meeting)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: 780, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onChange(of: app.searchQuery) {
            guard isSearching, let db = app.database else {
                searchResults = []
                return
            }
            searchResults = (try? db.searchMeetings(query: app.searchQuery)) ?? []
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: isSearching ? "magnifyingglass" : "calendar.badge.plus")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textTertiary)
            Text(isSearching ? "No results for \"\(app.searchQuery)\"" : "No meetings yet")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if !isSearching {
                Text("Hit Record when a meeting starts, or create a quick note.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }
}

private struct HeroEventCard: View {
    @Environment(AppState.self) private var app
    let event: CalendarMeeting

    var body: some View {
        HStack(spacing: 18) {
            VStack(spacing: 2) {
                Text(event.start, format: .dateTime.day())
                    .font(.system(size: 32, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                Text(event.start, format: .dateTime.month(.wide))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                Text(event.start, format: .dateTime.weekday(.wide))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(minWidth: 76)

            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.accent)
                .frame(width: 3, height: 52)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(event.start, format: .dateTime.hour().minute()) – \(event.end, format: .dateTime.hour().minute())")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if let url = event.joinURL {
                Link(destination: url) {
                    Label("Join", systemImage: "video")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)
                .tint(.white)
            }
            Button {
                app.startRecording(fromEvent: event)
            } label: {
                Label("Record", systemImage: "record.circle")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .disabled(app.recorder.isRecording)
        }
        .padding(20)
        .card(cornerRadius: 14)
    }
}

private struct HomeMeetingRow: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting

    private var folder: Folder? { app.folder(for: meeting) }

    var body: some View {
        Button {
            app.selectedMeetingID = meeting.id
        } label: {
            HStack(spacing: 12) {
                AvatarView(letterSource: folder.map { $0.team ?? $0.name })

                VStack(alignment: .leading, spacing: 2) {
                    Text(meeting.title)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if meeting.status == .recording {
                            Label("Recording", systemImage: "record.circle")
                                .font(.system(size: 11.5))
                                .foregroundStyle(.red)
                        } else if meeting.status == .processing {
                            Label("Processing", systemImage: "gearshape.2")
                                .font(.system(size: 11.5))
                                .foregroundStyle(Theme.textSecondary)
                        } else {
                            Text(folder?.name ?? "Me")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                if folder != nil {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text(meeting.createdAt, format: .dateTime.hour().minute())
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(cornerRadius: 10)
        .contextMenu {
            Menu("Move to folder") {
                Button("No folder") {
                    app.moveMeeting(meetingID: meeting.id, toFolder: nil)
                }
                ForEach(app.folders) { folder in
                    Button(folder.team.map { "\($0) / \(folder.name)" } ?? folder.name) {
                        app.moveMeeting(meetingID: meeting.id, toFolder: folder.id)
                    }
                }
            }
            Button("Delete", role: .destructive) {
                app.deleteMeeting(id: meeting.id)
            }
        }
    }
}
