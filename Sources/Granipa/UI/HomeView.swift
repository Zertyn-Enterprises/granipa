import SwiftUI

enum LibraryListPhase: Equatable, Sendable {
    case rows
    case pending
    case empty

    static func resolve(isEmpty: Bool, isSearching: Bool, searchInFlight: Bool) -> Self {
        if !isEmpty { return .rows }
        if isSearching && searchInFlight { return .pending }
        return .empty
    }
}

enum LibraryCopy {
    static func homeTitle(
        isSearching: Bool,
        folderName: String?
    ) -> String {
        if isSearching { return "Search" }
        if let folderName { return folderName }
        return "Home"
    }

    struct EmptyCopy: Equatable, Sendable {
        var icon: String
        var title: String
        var message: String?
        var showsQuickNote: Bool
        var showsRecord: Bool
    }

    static func emptyCopy(
        isSearching: Bool,
        query: String,
        filter: HomeLibraryFilter,
        folderName: String?
    ) -> EmptyCopy {
        if isSearching {
            return EmptyCopy(
                icon: "magnifyingglass",
                title: "No results for \"\(query)\"",
                message: nil,
                showsQuickNote: false,
                showsRecord: false)
        }
        let inFolder = folderName != nil
        switch filter {
        case .all:
            return EmptyCopy(
                icon: "calendar.badge.plus",
                title: inFolder ? "No meetings in this folder" : "No meetings yet",
                message: inFolder
                    ? "Move a meeting here from its row menu, or record a new one."
                    : "Record a meeting or start a quick note. Transcripts and notes land here.",
                showsQuickNote: true,
                showsRecord: true)
        case .notes:
            return EmptyCopy(
                icon: "square.and.pencil",
                title: inFolder ? "No notes in this folder" : "No notes yet",
                message: inFolder
                    ? "Move a meeting here from its row menu, or start a quick note."
                    : "Quick notes and meeting notes show up here.",
                showsQuickNote: true,
                showsRecord: false)
        case .recordings:
            return EmptyCopy(
                icon: "waveform",
                title: inFolder ? "No recordings in this folder" : "No recordings yet",
                message: inFolder
                    ? "Move a recording here from its row menu, or record a new one."
                    : "Record a meeting to capture mic and system audio files here.",
                showsQuickNote: false,
                showsRecord: true)
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

struct LibraryPendingSearch: View {
    var body: some View {
        ProgressView("Searching…")
            .controlSize(.small)
            .frame(maxWidth: .infinity)
            .padding(.top, 48)
            .foregroundStyle(Theme.textSecondary)
            .accessibilityLabel("Searching")
    }
}

struct LibraryMetaRow: View {
    var status: String? = nil
    var folder: String? = nil
    var duration: String? = nil
    let date: Date

    var body: some View {
        HStack(spacing: 6) {
            if let status, !status.isEmpty {
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.statusListening)
                    .lineLimit(1)
            }
            if let folder, !folder.isEmpty {
                MetadataBadge(text: folder)
            }
            Text(trailingParts.joined(separator: " · "))
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .monospacedDigit()
        }
    }

    private var trailingParts: [String] {
        var parts: [String] = []
        if let duration, !duration.isEmpty { parts.append(duration) }
        parts.append(LibraryCopy.dateLabel(date))
        return parts
    }
}

struct HomeView: View {
    @Environment(AppState.self) private var app
    @State private var searchResults: [Meeting] = []
    @State private var searchInFlight = false
    @State private var fileStatuses: [String: RecordingFileStatus] = [:]

    private var isSearching: Bool { MeetingLibrary.isSearching(app.searchQuery) }

    private var selectedFilter: HomeLibraryFilter {
        AppNavigation.activeLibraryFilter(
            destination: app.sidebarDestination,
            stored: app.homeLibraryFilter)
    }

    private var activeFolder: Folder? {
        app.selectedFolderID.flatMap { id in app.folders.first { $0.id == id } }
    }

    private var shownMeetings: [Meeting] {
        MeetingLibrary.shown(
            in: MeetingLibrary.libraryBase(
                meetings: app.meetings,
                searchResults: searchResults,
                isSearching: isSearching),
            filter: selectedFilter,
            folderID: app.selectedFolderID)
    }

    private var headerTitle: String {
        LibraryCopy.homeTitle(
            isSearching: isSearching,
            folderName: activeFolder?.name)
    }

    private var nextEvent: CalendarMeeting? {
        app.calendar.upcoming.first { $0.end > .now }
    }

    private var dayGroups: [(day: Date, meetings: [Meeting])] {
        MeetingLibrary.dayGroups(from: shownMeetings)
    }

    private var listPhase: LibraryListPhase {
        LibraryListPhase.resolve(
            isEmpty: shownMeetings.isEmpty,
            isSearching: isSearching,
            searchInFlight: searchInFlight)
    }

    private var empty: LibraryCopy.EmptyCopy {
        LibraryCopy.emptyCopy(
            isSearching: isSearching,
            query: app.searchQuery,
            filter: selectedFilter,
            folderName: activeFolder?.name)
    }

    private var fileStatusTaskID: [String] {
        selectedFilter == .recordings
            ? MeetingLibrary.recordingPaths(in: shownMeetings) : []
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: Theme.spaceM) {
                    DestinationHeader(title: headerTitle)
                    HomeLibraryFilterStrip(selection: selectedFilter, onSelect: selectFilter)
                }

                if AppNavigation.showsHomeCalendarCard(
                    filter: selectedFilter,
                    isSearching: isSearching,
                    hasFolder: app.selectedFolderID != nil),
                    let event = nextEvent
                {
                    HeroEventCard(event: event)
                }

                switch listPhase {
                case .pending:
                    LibraryPendingSearch()
                case .empty:
                    emptyState
                        .frame(maxWidth: .infinity)
                        .padding(.top, 48)
                case .rows:
                    ForEach(dayGroups, id: \.day) { group in
                        LazyVStack(alignment: .leading, spacing: 8) {
                            Text(Theme.dayHeader(group.day))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.bottom, 2)
                            ForEach(group.meetings) { meeting in
                                switch selectedFilter {
                                case .all:
                                    HomeMeetingRow(meeting: meeting)
                                case .notes:
                                    NotesLibraryRow(meeting: meeting)
                                case .recordings:
                                    FilesLibraryRow(
                                        meeting: meeting, fileStatuses: fileStatuses)
                                }
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
        .task(id: app.searchQuery) {
            let query = app.searchQuery
            guard MeetingLibrary.isSearching(query), let db = app.database else {
                searchResults = []
                searchInFlight = false
                return
            }
            searchInFlight = true
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) {
                (try? db.searchMeetings(query: query)) ?? []
            }.value
            guard MeetingLibrary.acceptSearch(
                finishedQuery: query,
                currentQuery: app.searchQuery,
                cancelled: Task.isCancelled)
            else { return }
            searchResults = results
            searchInFlight = false
        }
        .task(id: fileStatusTaskID) {
            let paths = fileStatusTaskID
            guard !paths.isEmpty else {
                fileStatuses = [:]
                return
            }
            let resolved = await Task.detached(priority: .utility) {
                MeetingLibrary.fileStatuses(for: paths)
            }.value
            guard !Task.isCancelled else { return }
            fileStatuses = resolved
        }
    }

    private func selectFilter(_ filter: HomeLibraryFilter) {
        let next = AppNavigation.selectingFilter(
            filter, destination: app.sidebarDestination)
        app.sidebarDestination = next.destination
        app.homeLibraryFilter = next.filter
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            EmptyStateView(icon: empty.icon, title: empty.title, message: empty.message)
            if empty.showsQuickNote || empty.showsRecord {
                HStack(spacing: 10) {
                    if empty.showsQuickNote {
                        Button {
                            app.createMeeting()
                        } label: {
                            Label("Quick note", systemImage: "plus")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .granipaSecondaryControl()
                        .accessibilityLabel("Quick note")
                    }
                    if empty.showsRecord {
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
                }
                .padding(.top, 4)
            }
        }
    }
}

private struct HomeLibraryFilterStrip: View {
    let selection: HomeLibraryFilter
    let onSelect: (HomeLibraryFilter) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HomeLibraryFilter.allCases) { item in
                let isSelected = selection == item
                Button {
                    onSelect(item)
                } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textSecondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(minHeight: 28)
                        .background(
                            isSelected ? Theme.accent.opacity(0.14) : Color.clear,
                            in: Capsule(style: .continuous)
                        )
                }
                .buttonStyle(PressFadeButtonStyle())
                .accessibilityLabel(item.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Library filter")
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

    var body: some View {
        Button {
            app.selectedMeetingID = meeting.id
        } label: {
            HStack(alignment: .top, spacing: 14) {
                AvatarView(
                    letterSource: meeting.title,
                    fallbackIcon: meeting.audioMicPath != nil || meeting.audioSystemPath != nil
                        ? "waveform" : "square.and.pencil",
                    size: 42)

                VStack(alignment: .leading, spacing: 6) {
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
                    LibraryMetaRow(
                        status: phase.isLive ? phase.label : nil,
                        folder: folder?.name,
                        duration: duration,
                        date: meeting.createdAt)
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
        .buttonStyle(PressFadeButtonStyle())
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
