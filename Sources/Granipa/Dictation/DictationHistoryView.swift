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

/// Load lifecycle for the history list: one place that decides what the UI
/// may truthfully show — first load, refresh, empty and error — while the
/// view keeps driving the real database fetch around it. Value type; no I/O.
struct DictationLibraryModel: Equatable {
    private(set) var entries: [DictationEntry] = []
    private(set) var total = 0
    private(set) var stats = DictationStats.empty
    private(set) var sourceApps: [String] = []
    /// Query whose snapshot `entries` holds; nil until the first success —
    /// the difference between "no dictations" and "not loaded yet".
    private(set) var appliedQuery: DictationLibraryQuery?
    /// Query of the fetch currently in flight; snapshots and failures for
    /// any other query are stragglers and get dropped.
    private(set) var inFlightQuery: DictationLibraryQuery?
    private(set) var loadFailed = false

    var isFirstLoad: Bool { inFlightQuery != nil && appliedQuery == nil }
    var isRefreshing: Bool { inFlightQuery != nil && appliedQuery != nil }
    /// A full-screen error is only honest when there is nothing to keep.
    var showsFullScreenError: Bool { loadFailed && appliedQuery == nil }
    var showsRefreshError: Bool { loadFailed && appliedQuery != nil }
    var showsEmptyState: Bool { appliedQuery != nil && entries.isEmpty }
    var showsPlaceholderStats: Bool { appliedQuery == nil && !loadFailed }

    mutating func begin(_ query: DictationLibraryQuery) {
        inFlightQuery = query
        loadFailed = false
    }

    mutating func succeed(_ snapshot: DictationLibrarySnapshot, query: DictationLibraryQuery) {
        guard query == inFlightQuery else { return }
        inFlightQuery = nil
        loadFailed = false
        appliedQuery = query
        entries = snapshot.entries
        total = snapshot.total
        stats = snapshot.stats
        sourceApps = snapshot.sourceApps
    }

    /// The fetch failed; last-good rows and stats stay exactly as applied.
    mutating func fail(query: DictationLibraryQuery) {
        guard query == inFlightQuery else { return }
        inFlightQuery = nil
        loadFailed = true
    }

    /// The in-flight fetch was superseded (paging took over its task).
    /// Neither a verdict nor an error: the rows on screen stay as applied.
    mutating func abandonInFlight() {
        inFlightQuery = nil
    }

    mutating func appendPage(_ snapshot: DictationLibrarySnapshot) {
        entries.append(contentsOf: snapshot.entries)
        total = snapshot.total
        stats = snapshot.stats
        sourceApps = snapshot.sourceApps
    }

    mutating func removeEntry(id: String) {
        entries.removeAll { $0.id == id }
        total = max(0, total - 1)
    }
}

struct DictationHistoryView: View {
    @Environment(AppState.self) private var app
    var onClose: (() -> Void)?

    @State private var period: DictationPeriod = .all
    @State private var search = ""
    @State private var appFilter: String?
    @State private var model = DictationLibraryModel()
    @State private var loadMoreFailed = false
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
        DictationLibraryFormat.dayGroups(from: model.entries)
    }

    var body: some View {
        Group {
            if isPanel {
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 12) {
                        filterRow
                        statsSection
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                    Rectangle().fill(Theme.border).frame(height: 1)
                    listScrollView
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        DictationDestinationHeader(dictation: app.dictation)
                        filterRow
                        statsSection
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
        .onDisappear {
            // A detached fetch outlives cancellation awaits; drop both the
            // load and the debounce so nothing applies into a dead view.
            loadTask?.cancel()
            searchDebounce?.cancel()
        }
        .onExitCommand { onClose?() }
        .onChange(of: period) { reload() }
        .onChange(of: appFilter) { reload() }
        // A commit persists (recordDictation writes before the observation
        // ticks), so a mounted list picks the new row up without a manual reload.
        .onChange(of: app.dictation.phase) { _, phase in
            if phase == .done { reload() }
        }
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

    /// The real metrics once a snapshot has applied; until then "—" cards of
    /// the same shape, so zeros never pose as measured data.
    @ViewBuilder
    private var statsSection: some View {
        if model.appliedQuery != nil {
            DictationStatsGrid(stats: model.stats)
        } else if model.showsPlaceholderStats {
            HStack(spacing: 10) {
                DictationStatCard(value: "—", label: "Words per minute", systemImage: "gauge")
                DictationStatCard(value: "—", label: "Words", systemImage: "text.word.spacing")
                DictationStatCard(
                    value: "—", label: "Est. time saved", systemImage: "clock",
                    help: "Typing time for these words at 40 words per minute.")
                DictationStatCard(value: "—", label: "Apps used", systemImage: "app")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Statistics loading")
        }
    }

    @ViewBuilder
    private var listContent: some View {
        if model.showsFullScreenError {
            errorState
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
        } else if model.isFirstLoad {
            loadingState
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
        } else if model.showsEmptyState {
            emptyState
                .frame(maxWidth: .infinity)
                .padding(.top, 50)
        } else {
            LazyVStack(alignment: .leading, spacing: 12) {
                refreshBanner
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
                if model.total > model.entries.count {
                    loadMoreFooter
                }
            }
        }
    }

    /// Truthful in-flight states for a list that already shows rows: the
    /// rows on screen are the last applied query's, never a mix.
    @ViewBuilder
    private var refreshBanner: some View {
        if model.isRefreshing {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.mini)
                Text("Updating results")
                    .font(Theme.fontSmall)
                    .foregroundStyle(Theme.textTertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Updating results")
        } else if model.showsRefreshError {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.statusFailed)
                Text("Couldn't refresh — showing previous results")
                    .font(Theme.fontSmall)
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 8)
                Button("Retry") {
                    reload()
                }
                .buttonStyle(.plain)
                .font(Theme.fontSmall)
                .foregroundStyle(Theme.accent)
                .accessibilityLabel("Retry refreshing history")
            }
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Loading history…")
                .font(Theme.fontSmall)
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading history")
    }

    /// Period, search and source filters sit above the metrics, matching the
    /// reference layout. The controls and their bindings are unchanged.
    private var filterRow: some View {
        HStack(spacing: 8) {
            Picker("Period", selection: $period) {
                ForEach(DictationPeriod.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Period")

            searchField

            appFilterMenu

            if isPanel {
                Button("Done") { onClose?() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .font(.system(size: 13, weight: .medium))
                    .accessibilityLabel("Close history")
            } else {
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
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
            TextField("Search dictations", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
                .accessibilityLabel("Search dictations")
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
        .background(
            Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
    }

    private var appFilterMenu: some View {
        Menu {
            Picker("App", selection: $appFilter) {
                Text("All apps").tag(String?.none)
                ForEach(model.sourceApps, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 11.5))
                Text(appFilter ?? "All apps")
                    .lineLimit(1)
                    .frame(maxWidth: 140, alignment: .leading)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(appFilter == nil ? Theme.textSecondary : Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous)
                    .stroke(Theme.border, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(model.sourceApps.isEmpty)
        .help("Filter by app")
        .accessibilityLabel("Filter by app")
    }

    private var loadMoreFooter: some View {
        VStack(spacing: 10) {
            if loadMoreFailed {
                Text("Couldn't load more")
                    .font(Theme.fontSmall)
                    .foregroundStyle(Theme.textTertiary)
                Button("Retry") {
                    loadMore()
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .controlSize(.regular)
                .accessibilityLabel("Retry loading more history")
            } else {
                Text(
                    "Showing \(model.entries.count.formatted()) of \(model.total.formatted())"
                )
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
                .accessibilityLabel(
                    "Load more, showing \(model.entries.count) of \(model.total)")
            }
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
            return "Tap \(DictationController.shortcutLabel) to start and stop, or hold to talk. Entries land here."
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

    private static func fetch(
        search: String,
        since: Date?,
        sourceApp: String?,
        limit: Int,
        before: (createdAt: Date, id: String)? = nil,
        database: AppDatabase?
    ) async -> DictationLibrarySnapshot? {
        guard let database else { return nil }
        let query = search.isEmpty ? nil : search
        return await Task.detached(priority: .userInitiated) {
            try? database.fetchDictationLibrarySnapshot(
                search: query, since: since, sourceApp: sourceApp,
                limit: limit, before: before)
        }.value
    }

    private func reload() {
        loadTask?.cancel()
        let query = DictationLibraryQuery(
            search: trimmedSearch, period: period, sourceApp: appFilter)
        let keeping = max(Self.pageSize, model.entries.count)
        model.begin(query)
        guard let database = app.database else {
            model.fail(query: query)
            return
        }
        loadTask = Task {
            let snapshot = await Self.fetch(
                search: query.search, since: query.since, sourceApp: query.sourceApp,
                limit: keeping, database: database)
            guard !Task.isCancelled else { return }
            apply(snapshot, query: query)
        }
    }

    private func loadMore() {
        guard !loadingMore, model.entries.count < model.total, let oldest = model.entries.last
        else { return }
        // The rows on screen still belong to the previous query (the reload after
        // a filter/search change is pending or still debounced); paging would mix
        // queries past the old cursor, and the reload must survive to replace them.
        // The applied query is the one that pages, so its frozen `since` bounds
        // the fetch — `.week` re-derives a later cutoff on every read.
        let current = DictationLibraryQuery(
            search: trimmedSearch, period: period, sourceApp: appFilter)
        guard let query = DictationLibraryQuery.pageQuery(
            applied: model.appliedQuery, current: current)
        else { return }
        loadTask?.cancel()
        model.abandonInFlight()
        loadingMore = true
        loadTask = Task {
            defer { loadingMore = false }
            let snapshot = await Self.fetch(
                search: query.search, since: query.since, sourceApp: query.sourceApp,
                limit: Self.pageSize,
                before: (createdAt: oldest.createdAt, id: oldest.id),
                database: app.database)
            guard !Task.isCancelled else { return }
            if let snapshot {
                loadMoreFailed = false
                model.appendPage(snapshot)
            } else if app.database != nil {
                loadMoreFailed = true
            }
        }
    }

    private func apply(_ snapshot: DictationLibrarySnapshot?, query: DictationLibraryQuery) {
        guard let snapshot else {
            model.fail(query: query)
            return
        }
        model.succeed(snapshot, query: query)
        loadMoreFailed = false
        if let filter = appFilter, !model.sourceApps.contains(filter) {
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
        model.removeEntry(id: entry.id)
        reload()
    }
}
