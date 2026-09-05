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
                    VStack(spacing: 14) {
                        EmptyStateView(
                            icon: isSearching ? "magnifyingglass" : "waveform",
                            title: isSearching
                                ? "No results for \"\(app.searchQuery)\""
                                : "No recordings yet",
                            message: isSearching
                                ? nil
                                : "Record a meeting to capture mic and system audio files here.")
                        if !isSearching {
                            Button {
                                app.startRecording()
                            } label: {
                                Label("Record", systemImage: "record.circle")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .granipaPrimaryControl()
                            .disabled(app.recorder.isBusy)
                            .accessibilityLabel("Record")
                            .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 48)
                } else {
                    Text("Recordings")
                        .font(Theme.sectionFont)
                        .foregroundStyle(Theme.textPrimary)

                    ForEach(MeetingLibrary.dayGroups(from: shown), id: \.day) { group in
                        LazyVStack(alignment: .leading, spacing: 8) {
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
    private var folder: Folder? { app.folder(for: meeting) }
    private var phase: MeetingPipelinePhase { app.pipelinePhase(for: meeting) }

    private var fileLines: [String] {
        var lines: [String] = []
        if let path = meeting.audioMicPath {
            lines.append(
                MeetingLibrary.fileLabel(
                    path: path, channel: "Me", status: fileStatuses[path]))
        }
        if let path = meeting.audioSystemPath {
            lines.append(
                MeetingLibrary.fileLabel(
                    path: path, channel: "Them", status: fileStatuses[path]))
        }
        return lines
    }

    private var meta: [String] {
        LibraryCopy.metaParts(
            status: isLive || phase.isLive ? (isLive ? "Recording" : phase.label) : nil,
            folder: folder?.name,
            duration: MeetingLibrary.durationLabel(from: meeting.startedAt, to: meeting.endedAt),
            date: meeting.createdAt)
    }

    var body: some View {
        Button {
            app.selectedMeetingID = meeting.id
        } label: {
            HStack(alignment: .top, spacing: 14) {
                AvatarView(letterSource: meeting.title, fallbackIcon: "waveform", size: 42)
                VStack(alignment: .leading, spacing: 5) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if isLive {
                        Text("Recording…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.statusListening)
                    } else if !fileLines.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(fileLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
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
        .accessibilityLabel(isLive ? "\(meeting.title), Recording" : meeting.title)
    }
}
