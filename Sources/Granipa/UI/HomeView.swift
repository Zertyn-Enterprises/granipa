import SwiftUI

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var searchResults: [Meeting] = []
    @State private var searchDebounce: Task<Void, Never>?

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
            LazyVStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Text(headerTitle)
                        .font(Theme.titleFont)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button {
                        app.createMeeting()
                    } label: {
                        Label("Quick note", systemImage: "plus")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(.white)
                    .accessibilityLabel("Quick note")
                    Button {
                        app.startRecording()
                    } label: {
                        Label(
                            app.recorder.isBusy ? "Recording…" : "Record",
                            systemImage: "record.circle"
                        )
                        .font(.system(size: 15, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.accent)
                    .recordGlow()
                    .disabled(app.recorder.isBusy)
                    .accessibilityLabel("Record")
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
                        LazyVStack(alignment: .leading, spacing: 6) {
                            Text(Theme.dayHeader(group.day))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.bottom, 2)
                            ForEach(group.meetings) { meeting in
                                HomeMeetingRow(meeting: meeting)
                            }
                        }
                        .padding(.bottom, 8)
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
            searchDebounce?.cancel()
            guard isSearching, let db = app.database else {
                searchResults = []
                return
            }
            let query = app.searchQuery
            searchDebounce = Task {
                try? await Task.sleep(for: .milliseconds(200))
                guard !Task.isCancelled else { return }
                let results = await Task.detached(priority: .userInitiated) {
                    (try? db.searchMeetings(query: query)) ?? []
                }.value
                guard !Task.isCancelled, query == app.searchQuery else { return }
                searchResults = results
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            EmptyStateView(
                icon: isSearching ? "magnifyingglass" : "calendar.badge.plus",
                title: isSearching
                    ? "No results for \"\(app.searchQuery)\""
                    : activeFolder != nil ? "No meetings in this folder" : "No meetings yet")
            if !isSearching {
                HStack(spacing: 10) {
                    Button {
                        app.createMeeting()
                    } label: {
                        Label("Quick note", systemImage: "plus")
                            .font(Theme.fontBody)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Theme.textSecondary)
                    .accessibilityLabel("Quick note")
                    Button {
                        app.startRecording()
                    } label: {
                        Label("Record", systemImage: "record.circle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .recordGlow()
                    .disabled(app.recorder.isBusy)
                    .accessibilityLabel("Record")
                }
                .padding(.top, 6)
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
                    .font(.system(size: 44, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                Text(event.start, format: .dateTime.month(.wide))
                    .font(Theme.fontCaption)
                    .foregroundStyle(Theme.textSecondary)
                Text(event.start, format: .dateTime.weekday(.wide))
                    .font(Theme.fontSmall)
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(minWidth: 76)

            RoundedRectangle(cornerRadius: 2)
                .fill(Theme.accent)
                .frame(width: 3, height: 64)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(event.start, format: .dateTime.hour().minute()) – \(event.end, format: .dateTime.hour().minute())")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            if let url = event.joinURL {
                Link(destination: url) {
                    Label("Join", systemImage: "video")
                        .font(.system(size: 15, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.white)
            }
            Button {
                app.startRecording(fromEvent: event)
            } label: {
                Label("Record", systemImage: "record.circle")
                    .font(.system(size: 15, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Theme.accent)
            .recordGlow()
            .disabled(app.recorder.isBusy)
            .accessibilityLabel("Record")
        }
        .padding(Theme.spaceXL)
        .card(cornerRadius: Theme.radiusL)
    }
}

private struct HomeMeetingRow: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting

    private var folder: Folder? { app.folder(for: meeting) }

    var body: some View {
        Button {
            app.showsDictationHistory = false
            app.selectedMeetingID = meeting.id
        } label: {
            HStack(spacing: 14) {
                MeetingGlyph(size: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        let phase = app.pipelinePhase(for: meeting)
                        if phase.isLive {
                            Label(phase.label, systemImage: phase.systemImage)
                                .font(Theme.fontSmall)
                                .foregroundStyle(phase.color)
                        } else if meeting.audioMicPath != nil {
                            MeetingSparklineView(seed: meeting.id)
                            Text(folder?.name ?? "Me")
                                .font(Theme.fontCaption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        } else {
                            Text(folder?.name ?? "Me")
                                .font(Theme.fontCaption)
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 8)

                Text(meeting.createdAt, format: .dateTime.hour().minute())
                    .font(Theme.fontCaption)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
        .hoverHighlight(cornerRadius: 14)
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
            Button("Export as Markdown…") {
                if let db = app.database {
                    MeetingExporter.exportViaSavePanel(
                        meeting: meeting, database: db, folder: folder)
                }
            }
            Button("Copy transcript") {
                if let db = app.database {
                    MeetingExporter.copyTranscript(meeting: meeting, database: db)
                }
            }
            Button("Delete", role: .destructive) {
                app.deleteMeeting(id: meeting.id)
            }
        }
    }
}
