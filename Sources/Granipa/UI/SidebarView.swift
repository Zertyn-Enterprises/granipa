import SwiftUI

struct SidebarView: View {
    @Environment(AppState.self) private var app
    @FocusState private var searchFocused: Bool
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var newFolderTeam = ""
    @State private var renamingFolder: Folder?
    @State private var renameText = ""

    private var highlight: SidebarHighlight {
        AppNavigation.highlight(
            destination: app.sidebarDestination,
            selectedFolderID: app.selectedFolderID)
    }

    private var folderCounts: [String: Int] {
        MeetingLibrary.folderCounts(from: app.meetings)
    }

    var body: some View {
        @Bindable var app = app
        VStack(alignment: .leading, spacing: 2) {
            Color.clear.frame(height: 34)

            brand
                .padding(.bottom, 12)

            searchField
                .padding(.bottom, 10)

            ForEach(SidebarDestination.allCases, id: \.self) { destination in
                SideItem(
                    title: destination.title,
                    icon: destination.icon,
                    isActive: highlight == .destination(destination)
                ) {
                    app.reveal(destination)
                }
                .accessibilityLabel(destination.title)
            }

            collectionsHeader
                .padding(.top, 18)
                .padding(.bottom, 4)

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
                                isActive: highlight == .folder(folder.id),
                                indented: group.team != nil,
                                quiet: true,
                                accessory: "\(folderCounts[folder.id, default: 0])"
                            ) {
                                app.revealFolder(id: folder.id)
                            }
                            .accessibilityLabel(folder.name)
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
                    .accessibilityLabel("Add folder")
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
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13))
                        .frame(width: 16)
                    Text("Settings")
                        .font(.system(size: 13))
                    Spacer()
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .hoverHighlight(cornerRadius: 10)
            .help("Settings")
            .accessibilityLabel("Settings")
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

    private var brand: some View {
        HStack(spacing: 8) {
            GranipaBrandMark()
            Text("Grañipa")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Grañipa")
    }

    private var collectionsHeader: some View {
        HStack(spacing: 8) {
            Text("COLLECTIONS")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .tracking(0.8)
            Spacer(minLength: 0)
            Button {
                showNewFolder = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Add folder")
            .accessibilityLabel("Add folder")
        }
        .padding(.leading, 8)
        .padding(.trailing, 4)
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
                .focused($searchFocused)
                .accessibilityLabel("Search Grañipa")
            if !app.searchQuery.isEmpty {
                Button {
                    app.searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            } else if !searchFocused {
                Text("⌘K")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Theme.fillSubtle, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
        .background {
            Button("Search Grañipa") { searchFocused = true }
                .keyboardShortcut("k", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
    }

    private var groupedFolders: [(team: String?, folders: [Folder])] {
        let grouped = Dictionary(grouping: app.folders) { $0.team }
        return grouped
            .sorted { ($0.key ?? "") < ($1.key ?? "") }
            .map { (team: $0.key, folders: $0.value.sorted { $0.name < $1.name }) }
    }
}

private struct GranipaBrandMark: View {
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            Capsule().fill(Theme.accent).frame(width: 2.5, height: 7)
            Capsule().fill(Theme.accent).frame(width: 2.5, height: 13)
            Capsule().fill(Theme.accent).frame(width: 2.5, height: 9)
            Capsule().fill(Theme.accent).frame(width: 2.5, height: 15)
        }
        .frame(width: 20, height: 16)
        .accessibilityHidden(true)
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
    var accessory: String? = nil
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
                if let accessory {
                    Text(accessory)
                        .font(.system(size: 12))
                        .foregroundStyle(isActive ? Theme.textSecondary : Theme.textTertiary)
                        .monospacedDigit()
                }
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
                    .fill(Theme.accent.opacity(0.14))
            }
        }
        .overlay(alignment: .leading) {
            if isActive {
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 3)
                    .padding(.vertical, 7)
                    .padding(.leading, 1)
            }
        }
        .hoverHighlight(cornerRadius: 10)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private var iconColor: Color {
        if let iconTint { return iconTint }
        if dimmed || (quiet && !isActive) { return Theme.textTertiary }
        return isActive ? Theme.accent : Theme.textSecondary
    }

    private var textColor: Color {
        if dimmed || (quiet && !isActive) { return Theme.textTertiary }
        return isActive ? Theme.textPrimary : Theme.textSecondary
    }
}
