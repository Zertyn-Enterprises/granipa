import SwiftUI

struct MeetingListView: View {
    @Environment(AppState.self) private var app
    @Binding var selection: String?
    @State private var searchQuery = ""
    @State private var searchResults: [Meeting] = []
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var newFolderTeam = ""
    @State private var renamingFolder: Folder?
    @State private var renameText = ""

    private var shownMeetings: [Meeting] {
        let base = searchQuery.isEmpty ? app.meetings : searchResults
        guard let folderID = app.selectedFolderID else { return base }
        return base.filter { $0.folderID == folderID }
    }

    private var meetingsSectionTitle: String {
        if let folderID = app.selectedFolderID,
            let folder = app.folders.first(where: { $0.id == folderID })
        {
            return folder.name
        }
        return "All notes"
    }

    var body: some View {
        List(selection: $selection) {
            upcomingSection
            foldersSection
            Section(meetingsSectionTitle) {
                ForEach(shownMeetings) { meeting in
                    MeetingRow(meeting: meeting, showFolder: app.selectedFolderID == nil)
                        .tag(meeting.id)
                        .contextMenu {
                            Menu("Move to folder") {
                                Button("No folder") {
                                    app.moveMeeting(meetingID: meeting.id, toFolder: nil)
                                }
                                ForEach(app.folders) { folder in
                                    Button(folderLabel(folder)) {
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
            if shownMeetings.isEmpty && searchQuery.isEmpty == false {
                ContentUnavailableView.search(text: searchQuery)
            }
        }
        .alert("New folder", isPresented: $showNewFolder) {
            TextField("Name", text: $newFolderName)
            TextField("Team (optional)", text: $newFolderTeam)
            Button("Create") {
                app.createFolder(
                    name: newFolderName,
                    team: newFolderTeam.isEmpty ? nil : newFolderTeam)
                newFolderName = ""
                newFolderTeam = ""
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename folder", isPresented: .constant(renamingFolder != nil)) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let folder = renamingFolder {
                    app.renameFolder(id: folder.id, name: renameText)
                }
                renamingFolder = nil
            }
            Button("Cancel", role: .cancel) { renamingFolder = nil }
        }
    }

    @ViewBuilder
    private var upcomingSection: some View {
        let upcoming = searchQuery.isEmpty ? app.calendar.upcoming.filter { $0.end > .now } : []
        if !upcoming.isEmpty {
            Section("Upcoming") {
                ForEach(upcoming) { event in
                    UpcomingRow(event: event)
                }
            }
        }
    }

    private var groupedFolders: [(team: String?, folders: [Folder])] {
        let grouped = Dictionary(grouping: app.folders) { $0.team }
        return grouped
            .sorted { ($0.key ?? "") < ($1.key ?? "") }
            .map { (team: $0.key, folders: $0.value.sorted { $0.name < $1.name }) }
    }

    @ViewBuilder
    private var foldersSection: some View {
        Section {
            FolderButton(
                name: "All notes",
                icon: "tray.full",
                isActive: app.selectedFolderID == nil
            ) {
                app.selectedFolderID = nil
            }
            ForEach(groupedFolders, id: \.team) { group in
                if let team = group.team {
                    Label(team, systemImage: "person.2")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                ForEach(group.folders) { folder in
                    FolderButton(
                        name: folder.name,
                        icon: "folder",
                        isActive: app.selectedFolderID == folder.id,
                        indented: group.team != nil
                    ) {
                        app.selectedFolderID = folder.id
                    }
                    .contextMenu {
                        Button("Rename") {
                            renameText = folder.name
                            renamingFolder = folder
                        }
                        Button("Delete", role: .destructive) {
                            app.deleteFolder(id: folder.id)
                        }
                    }
                }
            }
            Button {
                showNewFolder = true
            } label: {
                Label("New folder", systemImage: "folder.badge.plus")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        } header: {
            Text("Folders")
        }
    }

    private func folderLabel(_ folder: Folder) -> String {
        folder.team.map { "\($0) / \(folder.name)" } ?? folder.name
    }
}

private struct FolderButton: View {
    let name: String
    let icon: String
    let isActive: Bool
    var indented = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(name, systemImage: icon)
                .padding(.leading, indented ? 12 : 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fontWeight(isActive ? .semibold : .regular)
        .listRowBackground(
            isActive ? Color.accentColor.opacity(0.18) : nil
        )
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
    @Environment(AppState.self) private var app
    let meeting: Meeting
    var showFolder = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
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
                    Text(meeting.createdAt, format: .relative(presentation: .named))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if showFolder, let folder = app.folder(for: meeting) {
                    Label(folder.name, systemImage: "folder")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }
}
