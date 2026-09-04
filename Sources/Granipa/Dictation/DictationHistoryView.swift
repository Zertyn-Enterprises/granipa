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
    @State private var entries: [DictationEntry] = []
    @State private var stats = DictationStats.empty
    @State private var searchDebounce: Task<Void, Never>?
    @State private var targetApp: String?
    @FocusState private var searchFocused: Bool

    private var groups: [(day: Date, entries: [DictationEntry])] {
        let grouped = Dictionary(grouping: entries) {
            Calendar.current.startOfDay(for: $0.createdAt)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
    }

    var body: some View {
        VStack(spacing: 0) {
            statsBar
            searchBar
            Rectangle().fill(Theme.border).frame(height: 1)
            if entries.isEmpty {
                emptyState
            } else {
                historyList
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
        .onChange(of: search) {
            searchDebounce?.cancel()
            searchDebounce = Task {
                try? await Task.sleep(for: .milliseconds(140))
                guard !Task.isCancelled else { return }
                reload()
            }
        }
    }

    private var statsBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Period", selection: $period) {
                ForEach(DictationPeriod.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()

            HStack(spacing: 0) {
                statCell("\(stats.averageWPM) WPM", "Average speed")
                statCell(stats.words.formatted(), "Words")
                statCell("\(stats.apps)", "Apps used")
                statCell(stats.savedLabel(), "Saved")
            }
            .padding(.vertical, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14).stroke(Theme.border, lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private func statCell(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textTertiary)
            TextField("Search history", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .focused($searchFocused)
            if onClose != nil {
                Button("Done") { onClose?() }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textSecondary)
                    .font(.system(size: 13, weight: .medium))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "mic")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textTertiary)
            Text(search.isEmpty ? "No dictations yet" : "No matches")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if search.isEmpty {
                Text("Hold \(DictationController.shortcutLabel) to dictate. Entries land here.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var historyList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                ForEach(groups, id: \.day) { group in
                    Text(Theme.dayHeader(group.day))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 4)
                    ForEach(group.entries) { entry in
                        historyBubble(entry)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private func historyBubble(_ entry: DictationEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.text)
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8) {
                Text(entry.createdAt, format: .dateTime.hour().minute())
                if let appName = entry.sourceApp {
                    Text(appName)
                }
                Text("\(entry.wordCount) words")
            }
            .font(Theme.fontSmall)
            .foregroundStyle(Theme.textTertiary)
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusL))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusL).stroke(Theme.border, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusL))
        .onTapGesture { paste(entry) }
        .contextMenu {
            Button("Copy") { copy(entry) }
            Button("Paste") { paste(entry) }
            Button("Delete", role: .destructive) { delete(entry) }
        }
    }

    private func reload() {
        guard let db = app.database else { return }
        let since = period.since
        entries = (try? db.fetchDictationEntries(search: search, since: since)) ?? []
        stats = (try? db.dictationStats(since: since)) ?? .empty
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
        try? app.database?.deleteDictationEntry(id: entry.id)
        reload()
    }
}
