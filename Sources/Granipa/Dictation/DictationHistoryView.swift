import AppKit
import SwiftUI

enum DictationPeriod: String, CaseIterable, Identifiable {
    case today
    case week
    case all

    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: "Today"
        case .week: "Last 7 days"
        case .all: "All time"
        }
    }

    var since: Date? {
        switch self {
        case .today: Calendar.current.startOfDay(for: .now)
        case .week: Calendar.current.date(byAdding: .day, value: -7, to: .now)
        case .all: nil
        }
    }
}

struct DictationHistoryView: View {
    @Environment(AppState.self) private var app
    var onClose: (() -> Void)?

    @State private var period: DictationPeriod = .all
    @State private var search = ""
    @State private var appFilter: String?
    @State private var entries: [DictationEntry] = []
    @State private var total = 0
    @State private var stats = DictationStats.empty
    @State private var sourceApps: [String] = []
    @State private var loadFailed = false
    @State private var loadingMore = false
    @State private var loadTask: Task<Void, Never>?
    @State private var searchDebounce: Task<Void, Never>?
    @State private var targetApp: String?
    @FocusState private var searchFocused: Bool

    static let pageSize = 50

    private var isPanel: Bool { onClose != nil }

    private var trimmedSearch: String {
        search.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var groups: [(day: Date, entries: [DictationEntry])] {
        DictationLibraryFormat.dayGroups(from: entries)
    }

    var body: some View {
        Group {
            if isPanel {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        statsCard
                        toolbar
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 10)
                    Rectangle().fill(Theme.border).frame(height: 1)
                    listScrollView
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        DestinationHeader(title: "Dictation")
                        statsCard
                        toolbar
                        listContent
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(onClose == nil ? AnyShapeStyle(Theme.bg) : AnyShapeStyle(.ultraThinMaterial))
        .clipShape(RoundedRectangle(cornerRadius: onClose == nil ? 0 : Theme.radiusOverlay, style: .continuous))
        .overlay {
            if onClose != nil {
                RoundedRectangle(cornerRadius: Theme.radiusOverlay, style: .continuous)
                    .stroke(Theme.strokeStrong, lineWidth: 1)
            }
        }
        .preferredColorScheme(.dark)
        .background(primaryKeyShortcut)
        .onAppear {
            reload()
            searchFocused = onClose != nil
            let front = NSWorkspace.shared.frontmostApplication
            targetApp =
                front?.bundleIdentifier == Bundle.main.bundleIdentifier
                ? nil : front?.localizedName
        }
        .onExitCommand { onClose?() }
        .onChange(of: period) { reload() }
        .onChange(of: appFilter) { reload() }
        .onChange(of: search) {
            searchDebounce?.cancel()
            searchDebounce = Task {
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                reload()
            }
        }
    }

    private var listScrollView: some View {
        ScrollView {
            listContent
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if loadFailed {
            errorState
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
        } else if entries.isEmpty {
            emptyState
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(groups, id: \.day) { group in
                    Text(Theme.dayHeader(group.day))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                    ForEach(group.entries) { entry in
                        DictationEntryCard(
                            entry: entry,
                            tapCopies: onClose == nil,
                            onCopy: { copy(entry) },
                            onPaste: { paste(entry) },
                            onDelete: { delete(entry) })
                    }
                }
                if total > entries.count {
                    loadMoreFooter
                }
            }
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Picker("Period", selection: $period) {
                    ForEach(DictationPeriod.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Period")

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 10.5))
                    Text("Saved on device")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Theme.textTertiary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("History is saved on device")
            }

            Rectangle().fill(Theme.border).frame(height: 1)

            DictationStatsRow(stats: stats)
        }
        .padding(isPanel ? 12 : 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Search history", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($searchFocused)
                    .accessibilityLabel("Search history")
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear search")
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1))

            appFilterMenu

            if isPanel {
                Button("Done") { onClose?() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .font(.system(size: 13, weight: .medium))
                    .accessibilityLabel("Close history")
            }
        }
    }

    private var appFilterMenu: some View {
        Menu {
            Picker("App", selection: $appFilter) {
                Text("All apps").tag(String?.none)
                ForEach(sourceApps, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11.5))
                Text(appFilter ?? "All apps")
                    .lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(appFilter == nil ? Theme.textSecondary : Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(sourceApps.isEmpty)
        .help("Filter by app")
        .accessibilityLabel("Filter by app")
    }

    private var loadMoreFooter: some View {
        VStack(spacing: 10) {
            Text("Showing \(entries.count.formatted()) of \(total.formatted())")
                .font(Theme.fontSmall)
                .foregroundStyle(Theme.textTertiary)
                .monospacedDigit()
                .accessibilityHidden(true)
            Button {
                loadMore()
            } label: {
                HStack(spacing: 6) {
                    if loadingMore {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(loadingMore ? "Loading…" : "Load more")
                        .font(.system(size: 13, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
                .frame(height: 20)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.regular)
            .disabled(loadingMore)
            .accessibilityLabel("Load more, showing \(entries.count) of \(total)")
        }
        .padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            EmptyStateView(
                icon: trimmedSearch.isEmpty && appFilter == nil ? "mic" : "magnifyingglass",
                title: emptyTitle,
                message: emptyMessage
            )
        }
    }

    private var emptyTitle: String {
        if !trimmedSearch.isEmpty { return "No results for \"\(trimmedSearch)\"" }
        if appFilter != nil { return "No dictations from this app" }
        return "No dictations yet"
    }

    private var emptyMessage: String? {
        if trimmedSearch.isEmpty && appFilter == nil {
            return "Hold \(DictationController.shortcutLabel) to dictate. Entries land here."
        }
        if appFilter != nil && trimmedSearch.isEmpty {
            return "Try another period or pick a different app."
        }
        return "Try different words or check the filter."
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            EmptyStateView(
                icon: "exclamationmark.triangle",
                title: "Couldn't load history",
                message: "Reading the dictation database failed.")
            Button("Retry") {
                loadFailed = false
                reload()
            }
            .buttonStyle(.bordered)
            .tint(Theme.accent)
            .accessibilityLabel("Retry loading history")
        }
    }

    private var primaryKeyShortcut: some View {
        // ⌘F focuses this pane's search (contract §3.2). Invisible; only the shortcut matters.
        Button("Search history") { searchFocused = true }
            .keyboardShortcut("f", modifiers: .command)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    private struct Snapshot: Sendable {
        var entries: [DictationEntry]
        var total: Int
        var stats: DictationStats
        var sourceApps: [String]
    }

    private static func fetch(
        search: String,
        since: Date?,
        sourceApp: String?,
        limit: Int,
        offset: Int,
        database: AppDatabase?
    ) async -> Snapshot? {
        guard let database else { return nil }
        let query = search.isEmpty ? nil : search
        return await Task.detached(priority: .userInitiated) {
            guard let entries = try? database.fetchDictationEntries(
                search: query, since: since, sourceApp: sourceApp, limit: limit, offset: offset),
                let total = try? database.dictationEntryCount(
                    search: query, since: since, sourceApp: sourceApp),
                let stats = try? database.dictationStats(since: since),
                let sourceApps = try? database.dictationSourceApps(since: since)
            else { return nil }
            return Snapshot(
                entries: entries, total: total, stats: stats, sourceApps: sourceApps)
        }.value
    }

    private func reload() {
        loadTask?.cancel()
        let search = trimmedSearch
        let since = period.since
        let filter = appFilter
        let keeping = max(Self.pageSize, entries.count)
        loadTask = Task {
            let snapshot = await Self.fetch(
                search: search, since: since, sourceApp: filter,
                limit: keeping, offset: 0, database: app.database)
            guard !Task.isCancelled else { return }
            apply(snapshot, failureMeansFailed: app.database != nil)
        }
    }

    private func loadMore() {
        guard !loadingMore, entries.count < total else { return }
        loadingMore = true
        let search = trimmedSearch
        let since = period.since
        let filter = appFilter
        let offset = entries.count
        loadTask = Task {
            let snapshot = await Self.fetch(
                search: search, since: since, sourceApp: filter,
                limit: Self.pageSize, offset: offset, database: app.database)
            guard !Task.isCancelled else { return }
            loadingMore = false
            if let snapshot {
                loadFailed = false
                entries.append(contentsOf: snapshot.entries)
                total = snapshot.total
                stats = snapshot.stats
                sourceApps = snapshot.sourceApps
            } else if app.database != nil {
                loadFailed = true
            }
        }
    }

    private func apply(_ snapshot: Snapshot?, failureMeansFailed: Bool) {
        guard let snapshot else {
            if failureMeansFailed { loadFailed = true }
            return
        }
        loadFailed = false
        entries = snapshot.entries
        total = snapshot.total
        stats = snapshot.stats
        sourceApps = snapshot.sourceApps
        if let filter = appFilter, !snapshot.sourceApps.contains(filter) {
            appFilter = nil
        }
    }

    private func copy(_ entry: DictationEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        ToastController.shared.show("Copied")
    }

    private func paste(_ entry: DictationEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        guard onClose != nil else {
            ToastController.shared.show("Copied")
            return
        }
        onClose?()
        let appName = targetApp
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(140))
            if PasteService.pasteToFrontmostApp() {
                ToastController.shared.show(appName.map { "Pasted to \($0)" } ?? "Pasted")
            } else {
                ToastController.shared.show("Copied")
            }
        }
    }

    private func delete(_ entry: DictationEntry) {
        guard let database = app.database,
            (try? database.deleteDictationEntry(id: entry.id)) != nil
        else { return }
        entries.removeAll { $0.id == entry.id }
        total = max(0, total - 1)
        reload()
    }
}
