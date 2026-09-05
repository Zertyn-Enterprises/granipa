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
    @Environment(\.granipaWindowWidth) private var windowWidth
    @Bindable var dictation: DictationController

    private var compact: Bool { windowWidth < ShellLayout.inspectorBreakWidth }

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

            Button {
                app.createMeeting()
            } label: {
                if compact {
                    Image(systemName: "plus")
                } else {
                    Label("Quick note", systemImage: "plus")
                        .font(.system(size: 14, weight: .medium))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .tint(.white)
            .help("Quick note")
            .accessibilityLabel("Quick note")

            Button {
                dictation.toggleFromMenu()
            } label: {
                if compact {
                    Image(systemName: action.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                } else {
                    Label(action.title, systemImage: action.systemImage)
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

struct DictationStatCell: View {
    let value: String
    let label: String
    var help: String?

    var body: some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
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

struct DictationStatsRow: View {
    let stats: DictationStats

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 0) {
                DictationStatCell(value: "\(stats.averageWPM)", label: "Words per minute")
                DictationStatCell(value: stats.words.formatted(), label: "Words")
                DictationStatCell(
                    value: stats.savedLabel(),
                    label: "Est. time saved",
                    help: "Typing time for these words at 40 words per minute.")
                DictationStatCell(value: "\(stats.apps)", label: "Apps used")
            }
            VStack(spacing: 14) {
                HStack(spacing: 0) {
                    DictationStatCell(value: "\(stats.averageWPM)", label: "Words per minute")
                    DictationStatCell(value: stats.words.formatted(), label: "Words")
                }
                HStack(spacing: 0) {
                    DictationStatCell(
                        value: stats.savedLabel(),
                        label: "Est. time saved",
                        help: "Typing time for these words at 40 words per minute.")
                    DictationStatCell(value: "\(stats.apps)", label: "Apps used")
                }
            }
        }
    }
}

struct DictationEntryCard: View {
    let entry: DictationEntry
    let tapCopies: Bool
    let onCopy: () -> Void
    let onPaste: () -> Void
    let onDelete: () -> Void

    private var parts: (title: String, snippet: String) {
        DictationLibraryFormat.titleAndSnippet(entry.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(parts.title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(entry.createdAt, format: .dateTime.hour().minute())
                    .font(Theme.fontSmall)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }

            if !parts.snippet.isEmpty {
                Text(parts.snippet)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let appName = entry.sourceApp {
                    HStack(spacing: 4) {
                        Image(systemName: "macwindow")
                            .font(.system(size: 9))
                        Text(appName)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.fillSubtle, in: Capsule())
                }
                Text("\(entry.wordCount) words")
                Text(DictationLibraryFormat.duration(entry.durationSeconds))
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
            }
            .font(Theme.fontSmall)
            .foregroundStyle(Theme.textTertiary)
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
        .accessibilityLabel("\(parts.title), \(entry.wordCount) words")
    }
}
