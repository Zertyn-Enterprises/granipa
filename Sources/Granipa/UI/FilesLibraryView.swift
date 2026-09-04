import SwiftUI

struct FilesLibraryView: View {
    @Environment(AppState.self) private var app
    @State private var fileStatuses: [String: RecordingFileStatus] = [:]
    @State private var searchResults: [Meeting] = []

    private var isSearching: Bool {
        !app.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var shown: [Meeting] {
        isSearching ? searchResults : MeetingLibrary.recordings(in: app.meetings)
    }

    private var recordingPaths: [String] {
        var seen = Set<String>()
        var paths: [String] = []
        for meeting in MeetingLibrary.recordings(in: app.meetings) {
            for path in [meeting.audioMicPath, meeting.audioSystemPath].compactMap({ $0 }) {
                if seen.insert(path).inserted {
                    paths.append(path)
                }
            }
        }
        return paths
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                DestinationHeader(title: isSearching ? "Search" : "Files")

                if shown.isEmpty {
                    VStack(spacing: 10) {
                        EmptyStateView(
                            icon: isSearching ? "magnifyingglass" : "waveform",
                            title: isSearching
                                ? "No results for \"\(app.searchQuery)\""
                                : "No recordings yet")
                        if !isSearching {
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
                            .padding(.top, 6)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                } else {
                    Text("Recordings")
                        .font(Theme.sectionFont)
                        .foregroundStyle(Theme.textPrimary)

                    ForEach(MeetingLibrary.dayGroups(from: shown), id: \.day) { group in
                        LazyVStack(alignment: .leading, spacing: 6) {
                            Text(Theme.dayHeader(group.day))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.bottom, 2)
                            ForEach(group.meetings) { meeting in
                                FilesLibraryRow(meeting: meeting, fileStatuses: fileStatuses)
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
        .task(id: recordingPaths) {
            let paths = recordingPaths
            let resolved = await Task.detached(priority: .utility) {
                MeetingLibrary.fileStatuses(for: paths)
            }.value
            guard !Task.isCancelled else { return }
            fileStatuses = resolved
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
                MeetingLibrary.searchRecordings(query: query, database: db)
            }.value
            guard !Task.isCancelled else { return }
            searchResults = results
        }
    }
}

private struct FilesLibraryRow: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting
    let fileStatuses: [String: RecordingFileStatus]

    private var isLive: Bool { meeting.status == .recording }

    var body: some View {
        Button {
            app.selectedMeetingID = meeting.id
        } label: {
            HStack(alignment: .top, spacing: 14) {
                AvatarView(letterSource: meeting.title, fallbackIcon: "waveform", size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if isLive {
                        Text("Recording…")
                            .font(Theme.fontCaption)
                            .foregroundStyle(Theme.statusListening)
                    } else {
                        VStack(alignment: .leading, spacing: 2) {
                            if let path = meeting.audioMicPath {
                                Text(
                                    MeetingLibrary.fileLabel(
                                        path: path, channel: "Me", status: fileStatuses[path]))
                            }
                            if let path = meeting.audioSystemPath {
                                Text(
                                    MeetingLibrary.fileLabel(
                                        path: path, channel: "Them", status: fileStatuses[path]))
                            }
                            if let duration = MeetingLibrary.durationLabel(
                                from: meeting.startedAt, to: meeting.endedAt)
                            {
                                Text(duration)
                            }
                        }
                        .font(Theme.fontCaption)
                        .foregroundStyle(Theme.textSecondary)
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
        .accessibilityLabel(isLive ? "\(meeting.title), Recording" : meeting.title)
    }
}
