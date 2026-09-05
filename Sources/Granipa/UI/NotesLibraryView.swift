import SwiftUI

struct NotesLibraryView: View {
    @Environment(AppState.self) private var app
    @State private var searchResults: [Meeting] = []
    @State private var searchInFlight = false

    private var isSearching: Bool {
        !app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shown: [Meeting] {
        isSearching ? searchResults : MeetingLibrary.notes(in: app.meetings)
    }

    private var listPhase: LibraryListPhase {
        LibraryListPhase.resolve(
            isEmpty: shown.isEmpty,
            isSearching: isSearching,
            searchInFlight: searchInFlight)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                DestinationHeader(title: isSearching ? "Search" : "Notes")

                switch listPhase {
                case .pending:
                    LibraryPendingSearch()
                case .empty:
                    VStack(spacing: 14) {
                        EmptyStateView(
                            icon: isSearching ? "magnifyingglass" : "square.and.pencil",
                            title: isSearching
                                ? "No results for \"\(app.searchQuery)\""
                                : "No notes yet",
                            message: isSearching
                                ? nil
                                : "Quick notes and meeting notes show up here.")
                        if !isSearching {
                            Button {
                                app.createMeeting()
                            } label: {
                                Label("Quick note", systemImage: "plus")
                                    .font(.system(size: 14, weight: .medium))
                            }
                            .granipaSecondaryControl()
                            .accessibilityLabel("Quick note")
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                case .rows:
                    ForEach(MeetingLibrary.dayGroups(from: shown), id: \.day) { group in
                        LazyVStack(alignment: .leading, spacing: 8) {
                            Text(Theme.dayHeader(group.day))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.bottom, 2)
                            ForEach(group.meetings) { meeting in
                                NotesLibraryRow(meeting: meeting)
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
            guard isSearching, let db = app.database else {
                searchResults = []
                searchInFlight = false
                return
            }
            searchInFlight = true
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) {
                MeetingLibrary.searchNotes(query: query, database: db)
            }.value
            guard !Task.isCancelled else { return }
            searchResults = results
            searchInFlight = false
        }
    }
}

private struct NotesLibraryRow: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting

    private var folder: Folder? { app.folder(for: meeting) }
    private var phase: MeetingPipelinePhase { app.pipelinePhase(for: meeting) }
    private var excerpt: String {
        LibraryCopy.excerpt(
            summary: meeting.summary,
            enhancedNotesMarkdown: meeting.enhancedNotesMarkdown,
            notesMarkdown: meeting.notesMarkdown)
            ?? MeetingLibrary.notePreview(meeting)
    }

    var body: some View {
        Button {
            app.selectedMeetingID = meeting.id
        } label: {
            HStack(alignment: .top, spacing: 14) {
                AvatarView(letterSource: meeting.title, fallbackIcon: "square.and.pencil", size: 42)
                VStack(alignment: .leading, spacing: 6) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(excerpt)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                    LibraryMetaRow(
                        status: phase.isLive ? phase.label : nil,
                        folder: folder?.name,
                        duration: MeetingLibrary.durationLabel(
                            from: meeting.startedAt, to: meeting.endedAt),
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
        .accessibilityLabel("\(meeting.title), \(excerpt)")
    }
}
