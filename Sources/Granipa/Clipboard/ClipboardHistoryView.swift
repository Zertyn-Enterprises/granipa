import AppKit
import SwiftUI

struct ClipboardHistoryView: View {
    @Environment(AppState.self) private var app
    let onClose: () -> Void

    @State private var items: [ClipboardItem] = []
    @State private var groups: [(day: Date, items: [ClipboardItem])] = []
    @State private var search = ""
    @State private var filter: ClipboardItemType?
    @State private var selectedID: String?
    @State private var targetApp: String?
    @State private var searchDebounce: Task<Void, Never>?
    @FocusState private var searchFocused: Bool

    private var selected: ClipboardItem? {
        items.first { $0.id == selectedID } ?? items.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            HStack(spacing: 0) {
                list
                    .frame(width: 300)
                Rectangle().fill(Theme.border).frame(width: 1)
                preview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Rectangle().fill(Theme.border).frame(height: 1)
            footer
        }
        .frame(width: 800, height: 460)
        .background(Theme.bgSidebar)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
        .preferredColorScheme(.dark)
        .onAppear {
            reload()
            selectedID = items.first?.id
            searchFocused = true
            // The panel is non-activating, so the frontmost app is the paste target.
            let frontmost = NSWorkspace.shared.frontmostApplication
            targetApp =
                frontmost?.bundleIdentifier == Bundle.main.bundleIdentifier
                ? nil : frontmost?.localizedName
        }
        .onExitCommand { onClose() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(Theme.textTertiary)
            TextField("Type to filter entries…", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
                .onChange(of: search) {
                    searchDebounce?.cancel()
                    searchDebounce = Task {
                        try? await Task.sleep(for: .milliseconds(120))
                        guard !Task.isCancelled else { return }
                        reloadKeepingSelection()
                    }
                }
                .onKeyPress(.downArrow) {
                    moveSelection(1)
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    moveSelection(-1)
                    return .handled
                }
                .onKeyPress(.return) {
                    if let selected { copy(selected) }
                    return .handled
                }
            Picker("", selection: $filter) {
                Text("All Types").tag(ClipboardItemType?.none)
                Text("Text").tag(Optional(ClipboardItemType.text))
                Text("Links").tag(Optional(ClipboardItemType.link))
                Text("Images").tag(Optional(ClipboardItemType.image))
                Text("Files").tag(Optional(ClipboardItemType.file))
            }
            .labelsHidden()
            .frame(width: 110)
            .onChange(of: filter) { reloadKeepingSelection() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(groups, id: \.day) { group in
                        Text(Theme.dayHeader(group.day))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.top, 10)
                            .padding(.bottom, 3)
                        ForEach(group.items) { item in
                            ClipboardRow(item: item, isSelected: item.id == (selected?.id))
                                .id(item.id)
                                .onTapGesture {
                                    selectedID = item.id
                                    if NSApp.currentEvent?.clickCount == 2 {
                                        copy(item)
                                    }
                                }
                                .contextMenu {
                                    Button("Copy") { copy(item) }
                                    Button("Delete", role: .destructive) { delete(item) }
                                }
                        }
                    }
                    if items.isEmpty {
                        Text(search.isEmpty ? "Clipboard history is empty." : "No matches.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(14)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            .onChange(of: selectedID) {
                if let selectedID {
                    proxy.scrollTo(selectedID)
                }
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if let item = selected {
                    if item.type == .image,
                        let image = ImageCache.shared.preview(for: item)
                    {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(14)
                    } else {
                        ScrollView {
                            Text(item.textContent ?? "")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textPrimary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(14)
                        }
                    }
                } else {
                    Spacer()
                }
            }
            .frame(maxHeight: .infinity)

            if let item = selected {
                infoPanel(for: item)
            }
        }
    }

    private func infoPanel(for item: ClipboardItem) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Information")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            infoRow("Source", item.sourceApp ?? "Unknown")
            infoRow("Content type", item.type.rawValue.capitalized)
            if let width = item.width, let height = item.height {
                infoRow("Dimensions", "\(width)×\(height)")
            }
            if let size = item.sizeBytes {
                infoRow(
                    item.type == .image ? "Image size" : "Size",
                    ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
            }
            infoRow("Copied", item.createdAt.formatted(.relative(presentation: .named)))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03))
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard.fill")
                .font(.system(size: 12))
                .foregroundStyle(Theme.accent)
            Text("Clipboard History")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(autoPasteEnabled ? (targetApp.map { "Paste to \($0)" } ?? "Paste") : "Copy")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            Text("⏎")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Menu("Actions") {
                Button("Delete selected", role: .destructive) {
                    if let selected { delete(selected) }
                }
                Button("Clear all history", role: .destructive) { clearAll() }
            }
            .menuStyle(.borderlessButton)
            .font(.system(size: 12))
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    // MARK: - Actions

    private var autoPasteEnabled: Bool {
        UserDefaults.standard.object(forKey: "autoPasteEnabled") as? Bool ?? true
    }

    private func reload() {
        guard let db = app.database else { return }
        items = (try? db.fetchClipboardItems(search: search, type: filter)) ?? []
        let grouped = Dictionary(grouping: items) {
            Calendar.current.startOfDay(for: $0.createdAt)
        }
        groups = grouped
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }
    }

    private func reloadKeepingSelection() {
        reload()
        if !items.contains(where: { $0.id == selectedID }) {
            selectedID = items.first?.id
        }
    }

    private func moveSelection(_ delta: Int) {
        guard !items.isEmpty else { return }
        let currentIndex = items.firstIndex { $0.id == (selected?.id) } ?? 0
        let next = min(max(currentIndex + delta, 0), items.count - 1)
        selectedID = items[next].id
    }

    private func copy(_ item: ClipboardItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.type {
        case .image:
            if let path = item.imagePath, let data = FileManager.default.contents(atPath: path) {
                pasteboard.setData(data, forType: .png)
            }
        case .file:
            let urls = (item.textContent ?? "")
                .split(separator: "\n")
                .map { URL(fileURLWithPath: String($0)) as NSURL }
            pasteboard.writeObjects(urls)
        case .text, .link:
            pasteboard.setString(item.textContent ?? "", forType: .string)
        }
        onClose()

        if autoPasteEnabled {
            let appName = targetApp
            Task { @MainActor in
                // Give the panel a beat to order out so key events land in the target app.
                try? await Task.sleep(for: .milliseconds(140))
                if PasteService.pasteToFrontmostApp() {
                    ToastController.shared.show(appName.map { "Pasted to \($0)" } ?? "Pasted")
                } else {
                    ToastController.shared.show("Copied — grant Accessibility to auto-paste")
                }
            }
        } else {
            ToastController.shared.show("Copied to clipboard")
        }
    }

    private func delete(_ item: ClipboardItem) {
        guard let db = app.database else { return }
        if let path = try? db.deleteClipboardItem(id: item.id) {
            try? FileManager.default.removeItem(atPath: path)
        }
        reloadKeepingSelection()
    }

    private func clearAll() {
        guard let db = app.database else { return }
        let paths = (try? db.clearClipboardItems()) ?? []
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
        reloadKeepingSelection()
    }
}

private struct ClipboardRow: View {
    let item: ClipboardItem
    let isSelected: Bool

    private var icon: String {
        switch item.type {
        case .text: return "doc.text"
        case .link: return "link"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    private var thumbnail: NSImage? {
        item.type == .image ? ImageCache.shared.thumbnail(for: item) : nil
    }

    private var title: String {
        switch item.type {
        case .image:
            if let width = item.width, let height = item.height {
                return "Image (\(width)×\(height))"
            }
            return "Image"
        case .file:
            let first = (item.textContent ?? "").split(separator: "\n").first.map(String.init) ?? ""
            return (first as NSString).lastPathComponent
        case .text, .link:
            return (item.textContent ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
        }
    }

    var body: some View {
        HStack(spacing: 9) {
            if let image = thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22)
            }
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            isSelected ? Color.white.opacity(0.09) : .clear,
            in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }
}
