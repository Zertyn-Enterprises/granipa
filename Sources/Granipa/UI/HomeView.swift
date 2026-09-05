import SwiftUI

enum LibraryCopy {
    static func homeTitle(
        isSearching: Bool,
        folderName: String?,
        mode: HomeView.Mode
    ) -> String {
        if isSearching { return "Search" }
        if let folderName { return folderName }
        switch mode {
        case .inbox: return "Home"
        case .library: return "Meetings"
        }
    }

    static func excerpt(
        summary: String?,
        enhancedNotesMarkdown: String?,
        notesMarkdown: String
    ) -> String? {
        if let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty {
            return summary
        }
        for markdown in [enhancedNotesMarkdown ?? "", notesMarkdown] {
            let lines = plainLines(from: markdown, maxLines: 2)
            if !lines.isEmpty {
                return lines.joined(separator: "\n")
            }
        }
        return nil
    }

    static func plainLines(from markdown: String, maxLines: Int = Int.max) -> [String] {
        let blocks: [MarkdownBlock]
        if maxLines == Int.max {
            blocks = MarkdownParser.parse(markdown)
        } else {
            blocks = MarkdownParser.parse(markdown, maxBlocks: maxLines).blocks
        }
        return blocks.compactMap { block in
            switch block {
            case .heading(_, let text), .paragraph(let text), .bullet(_, let text),
                .numbered(_, _, let text):
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
        }
    }

    static func dateLabel(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    static func metaParts(
        status: String?,
        folder: String?,
        duration: String?,
        date: Date
    ) -> [String] {
        var parts: [String] = []
        if let status, !status.isEmpty { parts.append(status) }
        if let folder, !folder.isEmpty { parts.append(folder) }
        if let duration, !duration.isEmpty { parts.append(duration) }
        parts.append(dateLabel(date))
        return parts
    }
}

struct HomeView: View {
    enum Mode {
        case inbox
        case library
    }

    @Environment(AppState.self) private var app
    var mode: Mode = .inbox
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
        LibraryCopy.homeTitle(
            isSearching: isSearching,
            folderName: activeFolder?.name,
            mode: mode)
    }

    private var nextEvent: CalendarMeeting? {
        app.calendar.upcoming.first { $0.end > .now }
    }

    private var dayGroups: [(day: Date, meetings: [Meeting])] {
        MeetingLibrary.dayGroups(from: shownMeetings)
    }

    private var usesInboxLayout: Bool { mode == .inbox && activeFolder == nil }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                DestinationHeader(title: headerTitle)

                if usesInboxLayout, !isSearching, let event = nextEvent {
                    HeroEventCard(event: event)
                }

                if shownMeetings.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                } else {
                    ForEach(dayGroups, id: \.day) { group in
                        LazyVStack(alignment: .leading, spacing: 8) {
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
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(spacing: 14) {
            EmptyStateView(
                icon: isSearching ? "magnifyingglass" : "calendar.badge.plus",
                title: isSearching
                    ? "No results for \"\(app.searchQuery)\""
                    : activeFolder != nil ? "No meetings in this folder" : "No meetings yet",
                message: isSearching
                    ? nil
                    : activeFolder != nil
                        ? "Move a meeting here from its row menu, or record a new one."
                        : "Record a meeting or start a quick note. Transcripts and notes land here.")
            if !isSearching {
                HStack(spacing: 10) {
                    Button {
                        app.createMeeting()
                    } label: {
                        Label("Quick note", systemImage: "plus")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .granipaSecondaryControl()
                    .accessibilityLabel("Quick note")
                    Button {
                        app.startRecording()
                    } label: {
                        Label("Record", systemImage: "record.circle")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .granipaPrimaryControl()
                    .disabled(app.recorder.isBusy)
                    .accessibilityLabel("Record")
                }
                .padding(.top, 4)
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
                    .font(.system(size: 44, weight: .bold))
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
                .granipaSecondaryControl()
            }
            Button {
                app.startRecording(fromEvent: event)
            } label: {
                Label("Record", systemImage: "record.circle")
                    .font(.system(size: 15, weight: .semibold))
            }
            .granipaPrimaryControl()
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
    private var phase: MeetingPipelinePhase { app.pipelinePhase(for: meeting) }
    private var excerpt: String? {
        LibraryCopy.excerpt(
            summary: meeting.summary,
            enhancedNotesMarkdown: meeting.enhancedNotesMarkdown,
            notesMarkdown: meeting.notesMarkdown)
    }
    private var duration: String? {
        MeetingLibrary.durationLabel(from: meeting.startedAt, to: meeting.endedAt)
    }
    private var meta: [String] {
        LibraryCopy.metaParts(
            status: phase.isLive ? phase.label : nil,
            folder: folder?.name,
            duration: duration,
            date: meeting.createdAt)
    }

    var body: some View {
        Button {
            app.selectedMeetingID = meeting.id
        } label: {
            HStack(alignment: .top, spacing: 14) {
                AvatarView(
                    letterSource: meeting.title,
                    fallbackIcon: meeting.audioMicPath != nil || meeting.audioSystemPath != nil
                        ? "waveform" : "note.text",
                    size: 42)

                VStack(alignment: .leading, spacing: 5) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if let excerpt {
                        Text(excerpt)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }
                    if !meta.isEmpty {
                        Text(meta.joined(separator: " · "))
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                Text(meeting.createdAt, format: .dateTime.hour().minute())
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .card(cornerRadius: Theme.radiusM)
        .hoverHighlight(cornerRadius: Theme.radiusM)
        .contextMenu {
            MeetingRowContextMenu(meeting: meeting)
        }
    }
}

struct MeetingRowContextMenu: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting

    private var folder: Folder? { app.folder(for: meeting) }

    var body: some View {
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
