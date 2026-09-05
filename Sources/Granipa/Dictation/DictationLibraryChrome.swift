import SwiftUI

/// What the Dictation page's primary button shows for a controller phase.
/// Mirrors the menu bar's capture section: stop while live, no dead button
/// while transcribing, and a mic conflict only disables starting.
enum DictationHeaderAction: Equatable {
    case record(disabled: Bool)
    case stop
    case transcribing

    static func resolve(phase: DictationPhase, recorderBusy: Bool) -> DictationHeaderAction {
        switch phase {
        case .preparing, .listening: .stop
        case .processing: .transcribing
        case .idle, .done, .failed: .record(disabled: recorderBusy)
        }
    }

    var title: String {
        switch self {
        case .record: "Record"
        case .stop: "Stop"
        case .transcribing: "Transcribing…"
        }
    }

    var systemImage: String {
        switch self {
        case .record: "record.circle"
        case .stop: "stop.circle.fill"
        case .transcribing: "waveform"
        }
    }

    var isEnabled: Bool {
        switch self {
        case .record(let disabled): !disabled
        case .stop: true
        case .transcribing: false
        }
    }
}

/// The Dictation destination header: its primary button drives dictation
/// (`toggleFromMenu()`), never meeting recording. Quick note keeps the
/// shared destination action.
struct DictationDestinationHeader: View {
    @Environment(AppState.self) private var app
    @Bindable var dictation: DictationController

    private var action: DictationHeaderAction {
        DictationHeaderAction.resolve(
            phase: dictation.phase, recorderBusy: app.recorder.isBusy)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Theme.accent.opacity(0.16))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Dictation")
                    .font(Theme.titleFont)
                    .foregroundStyle(Theme.textPrimary)
                Text("Capture your voice. We'll handle the rest.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 12)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    quickNoteButton(labeled: true)
                    recordButton(labeled: true)
                }
                HStack(spacing: 14) {
                    quickNoteButton(labeled: false)
                    recordButton(labeled: true)
                }
                HStack(spacing: 14) {
                    quickNoteButton(labeled: false)
                    recordButton(labeled: false)
                }
            }
            .layoutPriority(1)
        }
    }

    private func quickNoteButton(labeled: Bool) -> some View {
        Button {
            app.createMeeting()
        } label: {
            if labeled {
                Label("Quick note", systemImage: "plus")
                    .font(.system(size: 14, weight: .medium))
            } else {
                Image(systemName: "plus")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(.white)
        .help("Quick note")
        .accessibilityLabel("Quick note")
    }

    private func recordButton(labeled: Bool) -> some View {
        Button {
            dictation.toggleFromMenu()
        } label: {
            if labeled {
                Label(action.title, systemImage: action.systemImage)
                    .font(.system(size: 15, weight: .semibold))
            } else {
                Image(systemName: action.systemImage)
                    .font(.system(size: 15, weight: .semibold))
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(Theme.accent)
        .recordGlow()
        .disabled(!action.isEnabled)
        .help(helpText)
        .accessibilityLabel(action == .stop ? "Stop dictation" : action.title)
    }

    private var helpText: String {
        switch action {
        case .stop: "Stop dictation"
        case .transcribing: "Transcribing…"
        case .record(true): "Mic in use — meeting recording"
        case .record(false): "Record dictation"
        }
    }
}

enum DictationLibraryFormat {
    /// Compact `m:ss` / `h:mm:ss` label from a duration in seconds.
    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, total % 60)
        }
        return String(format: "%d:%02d", minutes, total % 60)
    }

    /// The first line is the card title; the remaining lines are the snippet.
    static func titleAndSnippet(_ text: String) -> (title: String, snippet: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (title: text, snippet: "") }
        let lines = trimmed.split(whereSeparator: \.isNewline)
        let title = String(lines[0]).trimmingCharacters(in: .whitespaces)
        let snippet = lines.dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        return (title: title, snippet: snippet)
    }

    /// What the card renders: a title line only when more lines follow it —
    /// a single-paragraph dictation displayed once as the excerpt, never
    /// repeated as both title and snippet. Copy/paste still use the full text.
    static func displayParts(_ text: String) -> (title: String?, excerpt: String) {
        let parts = titleAndSnippet(text)
        if parts.snippet.isEmpty {
            return (title: nil, excerpt: parts.title)
        }
        return (title: parts.title, excerpt: parts.snippet)
    }

    static func dayGroups(
        from entries: [DictationEntry]
    ) -> [(day: Date, entries: [DictationEntry])] {
        let grouped = Dictionary(grouping: entries) {
            Calendar.current.startOfDay(for: $0.createdAt)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, entries: $0.value.sorted { $0.createdAt > $1.createdAt }) }
    }
}

/// The (search, period, app) selection a history snapshot was fetched under,
/// plus the `since` cutoff frozen when the query was built. The rows on
/// screen, their paging cursor and any page must describe the same selection,
/// so that triple is the identity the list pages under — never `since`, which
/// `.week` re-derives from `.now` on every read.
struct DictationLibraryQuery: Equatable, Sendable {
    var search: String
    var period: DictationPeriod
    var sourceApp: String?
    var since: Date?

    init(search: String, period: DictationPeriod, sourceApp: String?) {
        self.search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        self.period = period
        self.sourceApp = sourceApp
        self.since = period.since
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.search == rhs.search && lhs.period == rhs.period
            && lhs.sourceApp == rhs.sourceApp
    }

    /// The query a page of the rows on screen runs under: the applied one —
    /// carrying the cutoff those rows were fetched with — when the current
    /// selection still matches it, nil otherwise. After a filter or period
    /// change, while the reload is pending or still inside the search debounce,
    /// the rows belong to the previous query and the reload must replace them.
    static func pageQuery(
        applied: DictationLibraryQuery?, current: DictationLibraryQuery
    ) -> DictationLibraryQuery? {
        guard let applied, applied == current else { return nil }
        return applied
    }
}

struct DictationStatCard: View {
    let value: String
    let label: String
    let systemImage: String
    var help: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent.opacity(0.9))
                .frame(width: 22, height: 22)
                .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            Text(value)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 10.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value), \(label)")
        .modifier(OptionalHelp(help: help))
    }
}

private struct OptionalHelp: ViewModifier {
    let help: String?

    func body(content: Content) -> some View {
        if let help {
            content.help(help)
        } else {
            content
        }
    }
}

/// The four real history metrics as separate cards. The time-saved figure is
/// an estimate — its label carries the qualifier and its help states the
/// 40 wpm basis.
struct DictationStatsGrid: View {
    let stats: DictationStats

    var body: some View {
        ViewThatFits(in: .horizontal) {
            row
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    card(
                        value: "\(stats.averageWPM)", label: "Words per minute",
                        systemImage: "gauge")
                    card(
                        value: stats.words.formatted(), label: "Words",
                        systemImage: "text.word.spacing")
                }
                HStack(spacing: 10) {
                    card(
                        value: stats.savedLabel(), label: "Est. time saved",
                        systemImage: "clock",
                        help: "Typing time for these words at 40 words per minute.")
                    card(
                        value: "\(stats.apps)", label: "Apps used",
                        systemImage: "app")
                }
            }
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            card(
                value: "\(stats.averageWPM)", label: "Words per minute",
                systemImage: "gauge")
            card(
                value: stats.words.formatted(), label: "Words",
                systemImage: "text.word.spacing")
            card(
                value: stats.savedLabel(), label: "Est. time saved",
                systemImage: "clock",
                help: "Typing time for these words at 40 words per minute.")
            card(
                value: "\(stats.apps)", label: "Apps used",
                systemImage: "app")
        }
    }

    private func card(value: String, label: String, systemImage: String, help: String? = nil)
        -> some View
    {
        DictationStatCard(
            value: value, label: label, systemImage: systemImage, help: help)
    }
}

struct DictationEntryCard: View {
    let entry: DictationEntry
    let tapCopies: Bool
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onDelete: () -> Void

    private var parts: (title: String?, excerpt: String) {
        DictationLibraryFormat.displayParts(entry.text)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            appBadge

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let title = parts.title {
                        Text(title)
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text(entry.createdAt, format: .dateTime.hour().minute())
                        .font(Theme.fontSmall)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }

                Text(parts.excerpt)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    if let appName = entry.sourceApp {
                        Text(appName)
                    }
                    Text(DictationLibraryFormat.duration(entry.durationSeconds))
                    Text("\(entry.wordCount) words")
                    Spacer(minLength: 8)
                    Button(action: onCopy) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Copy")
                    .accessibilityLabel("Copy")
                    Button(action: onPaste) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 22, height: 22)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Paste to frontmost app")
                    .accessibilityLabel("Paste")
                    overflowMenu
                }
                .font(Theme.fontSmall)
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
        .hoverHighlight(cornerRadius: Theme.radiusM)
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .onTapGesture { tapCopies ? onCopy() : onPaste() }
        .contextMenu {
            Button("Copy") { onCopy() }
            Button("Paste") { onPaste() }
            Button("Delete", role: .destructive) { onDelete() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(accessibilityTitle), \(entry.wordCount) words")
    }

    private var accessibilityTitle: String {
        parts.title ?? entry.text.replacingOccurrences(of: "\n", with: " ")
    }

    private var appBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(
                    entry.sourceApp.map { Theme.avatarColor(for: $0).opacity(0.85) }
                        ?? Theme.fillSubtle)
            if let appName = entry.sourceApp, let first = appName.first {
                Text(String(first).uppercased())
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Image(systemName: "mic")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(width: 30, height: 30)
        .accessibilityHidden(true)
    }

    private var overflowMenu: some View {
        Menu {
            Button("Copy") { onCopy() }
            Button("Paste") { onPaste() }
            Divider()
            Button("Delete", role: .destructive) { onDelete() }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .buttonStyle(.plain)
        .help("More actions")
        .accessibilityLabel("More actions")
    }
}
