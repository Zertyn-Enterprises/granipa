import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var newFolderTeam = ""
    @State private var renamingFolder: Folder?
    @State private var renameText = ""

    private var isHomeActive: Bool {
        !app.showsDictationHistory && app.selectedFolderID == nil
    }

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 34)

            searchField
                .padding(.bottom, 10)

            SideItem(title: "Home", icon: "house.fill", isActive: isHomeActive) {
                app.selectedMeetingID = nil
                app.selectedFolderID = nil
                app.searchQuery = ""
                app.showsDictationHistory = false
            }

            SideItem(
                title: "Dictation",
                icon: "mic.fill",
                isActive: app.showsDictationHistory
            ) {
                app.selectedMeetingID = nil
                app.selectedFolderID = nil
                app.searchQuery = ""
                app.showsDictationHistory = true
            }

            if !app.folders.isEmpty {
                Text("SPACES")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .tracking(0.8)
                    .padding(.top, 18)
                    .padding(.bottom, 4)
                    .padding(.leading, 8)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(groupedFolders, id: \.team) { group in
                        if let team = group.team {
                            HStack(spacing: 7) {
                                AvatarView(letterSource: team, size: 18)
                                Text(team)
                                    .font(.system(size: 12.5, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                            .padding(.bottom, 2)
                        }
                        ForEach(group.folders) { folder in
                            SideItem(
                                title: folder.name,
                                icon: "folder",
                                isActive: app.selectedFolderID == folder.id,
                                indented: group.team != nil,
                                quiet: true
                            ) {
                                app.selectedFolderID = folder.id
                                app.selectedMeetingID = nil
                                app.showsDictationHistory = false
                                app.searchQuery = ""
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
                    SideItem(title: "Add folder", icon: "folder.badge.plus", isActive: false, dimmed: true) {
                        showNewFolder = true
                    }
                    .padding(.top, 4)
                }
            }

            Spacer(minLength: 8)

            if app.recorder.isRecording {
                HStack(spacing: 7) {
                    Circle().fill(Theme.statusListening).frame(width: 7, height: 7)
                    Text("Recording")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }

            SettingsLink {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight()
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
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

    private var searchField: some View {
        @Bindable var app = app
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            TextField("Search", text: $app.searchQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
            if !app.searchQuery.isEmpty {
                Button {
                    app.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Theme.fillSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
    }

    private var groupedFolders: [(team: String?, folders: [Folder])] {
        let grouped = Dictionary(grouping: app.folders) { $0.team }
        return grouped
            .sorted { ($0.key ?? "") < ($1.key ?? "") }
            .map { (team: $0.key, folders: $0.value.sorted { $0.name < $1.name }) }
    }
}

private struct SideItem: View {
    let title: String
    let icon: String
    let isActive: Bool
    var indented = false
    var dimmed = false
    var quiet = false
    var iconTint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(Theme.fontCaption.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 16)
                Text(title)
                    .font(isActive ? Theme.fontBody.weight(.semibold) : Theme.fontBody)
                    .foregroundStyle(textColor)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .padding(.leading, indented ? 14 : 0)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Theme.fillSubtle)
            }
        }
        .hoverHighlight(cornerRadius: 10)
    }

    private var iconColor: Color {
        if let iconTint { return iconTint }
        if dimmed || (quiet && !isActive) { return Theme.textTertiary }
        return isActive ? Theme.textPrimary : Theme.textSecondary
    }

    private var textColor: Color {
        if dimmed || (quiet && !isActive) { return Theme.textTertiary }
        return isActive ? Theme.textPrimary : Theme.textSecondary
    }
}
