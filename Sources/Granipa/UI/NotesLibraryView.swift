import SwiftUI

struct NotesLibraryView: View {
    @Environment(AppState.self) private var app
    @State private var searchResults: [Meeting] = []

    private var isSearching: Bool {
        !app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shown: [Meeting] {
        isSearching ? searchResults : MeetingLibrary.notes(in: app.meetings)
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                DestinationHeader(title: isSearching ? "Search" : "Notes")

                if shown.isEmpty {
                    VStack(spacing: 10) {
                        EmptyStateView(
                            icon: isSearching ? "magnifyingglass" : "note.text",
                            title: isSearching
                                ? "No results for \"\(app.searchQuery)\""
                                : "No notes yet")
                        if !isSearching {
                            Button {
                                app.createMeeting()
                            } label: {
                                Label("Quick note", systemImage: "plus")
                                    .font(Theme.fontBody)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Theme.textSecondary)
                            .accessibilityLabel("Quick note")
                            .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    ForEach(MeetingLibrary.dayGroups(from: shown), id: \.day) { group in
                        LazyVStack(alignment: .leading, spacing: 6) {
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
                return
            }
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            let results = await Task.detached(priority: .userInitiated) {
                MeetingLibrary.searchNotes(query: query, database: db)
            }.value
            guard !Task.isCancelled else { return }
            searchResults = results
        }
    }
}

private struct NotesLibraryRow: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting

    var body: some View {
        Button {
            app.selectedMeetingID = meeting.id
        } label: {
            HStack(alignment: .top, spacing: 14) {
                AvatarView(letterSource: meeting.title, fallbackIcon: "note.text", size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(MeetingLibrary.notePreview(meeting))
                        .font(Theme.fontCaption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
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
        .accessibilityLabel("\(meeting.title), \(MeetingLibrary.notePreview(meeting))")
    }
}
