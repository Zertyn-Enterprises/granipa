import SwiftUI

/// One meeting's enhanced-notes markdown as renderable blocks: a bounded
/// prefix parses synchronously so tab entry paints immediately, the full
/// document parses off the main actor, and the result is cached for the
/// source it came from (a re-enhance invalidates it).
@MainActor
@Observable
final class EnhancedNotesDocument {
    static let previewBlockLimit = 30

    private(set) var blocks: [MarkdownBlock] = []
    private(set) var isComplete = false
    /// The source `blocks` currently render. Until `.task` runs `update`,
    /// this differs from the meeting's notes and the view shows preparation
    /// instead of flashing the previous source's blocks.
    private(set) var source = ""
    private var inFlight = false
    private var generation = 0

    func update(source newSource: String) {
        if newSource == source, isComplete || inFlight { return }
        generation += 1
        let current = generation
        source = newSource
        isComplete = false
        let prefix = MarkdownParser.parse(newSource, maxBlocks: Self.previewBlockLimit).blocks
        blocks = prefix
        // Fewer blocks than the limit means the prefix reached the end of
        // the document; there is nothing left to parse in the background.
        guard prefix.count >= Self.previewBlockLimit else {
            isComplete = true
            inFlight = false
            return
        }
        inFlight = true
        Task {
            let full = await Task.detached(priority: .userInitiated) {
                MarkdownParser.parse(newSource)
            }.value
            guard current == generation else { return }
            blocks = full
            isComplete = true
            inFlight = false
        }
    }
}

struct EnhancedNotesView: View {
    @Environment(AppState.self) private var app
    let meetingID: String
    let document: EnhancedNotesDocument

    @State private var emailExpanded = false

    private var meeting: Meeting? {
        app.meetings.first { $0.id == meetingID }
    }

    private var isEnhancing: Bool {
        app.enhancingMeetingIDs.contains(meetingID)
    }

    var body: some View {
        Group {
            if isEnhancing {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Writing notes with \(providerName())…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Your rough notes and the transcript are being turned into the final report.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let meeting, let notes = meeting.enhancedNotesMarkdown {
                content(for: meeting, notes: notes)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "wand.and.stars")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.textTertiary)
                    Text("No enhanced notes yet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("Enhancement runs automatically when a recording ends.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                    enhanceButton(title: "Enhance now")
                        .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Document

    private func content(for meeting: Meeting, notes: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let summary = meeting.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Summary", systemImage: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        MarkdownText(markdown: summary)
                            .font(.system(size: 14))
                            .lineSpacing(6)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card(cornerRadius: Theme.radiusL)
                }

                if document.source == notes {
                    MarkdownBlocksView(blocks: document.blocks)
                } else if !notes.isEmpty {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Formatting notes…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }

                let items = ActionItem.decodeList(from: meeting.actionItemsJSON)
                if !items.isEmpty {
                    sectionHeader("Action items")
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            ActionItemRow(item: item) {
                                app.toggleActionItem(meetingID: meeting.id, index: index)
                            }
                        }
                    }
                }

                if let draft = meeting.emailDraft, !draft.isEmpty {
                    sectionHeader("Follow-up email")
                    DisclosureGroup(isExpanded: $emailExpanded) {
                        VStack(alignment: .leading, spacing: 10) {
                            MarkdownText(markdown: draft)
                                .font(.system(size: 13.5))
                                .lineSpacing(3)
                                .foregroundStyle(Theme.textPrimary)
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(draft, forType: .string)
                                ToastController.shared.show("Email copied")
                            } label: {
                                Label("Copy email", systemImage: "doc.on.doc")
                                    .font(.system(size: 12, weight: .medium))
                            }
                            .buttonStyle(.bordered)
                            .tint(.white)
                        }
                        .padding(.top, 10)
                    } label: {
                        Text(emailExpanded ? "Hide draft" : "Show draft")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .tint(Theme.textTertiary)
                }

                HStack {
                    enhanceButton(title: "Re-enhance")
                    Spacer()
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: notes) { document.update(source: notes) }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Theme.sectionFont)
            .foregroundStyle(Theme.textPrimary)
            .padding(.top, 6)
    }

    private func enhanceButton(title: String) -> some View {
        Button {
            Task { await app.enhance(meetingID: meetingID) }
        } label: {
            Label(title, systemImage: "wand.and.stars")
                .font(.system(size: 13, weight: .medium))
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .disabled(isEnhancing || app.recorder.meetingID == meetingID)
    }

    private func providerName() -> String {
        let id = UserDefaults.standard.string(forKey: "llmProvider") ?? "claude"
        return LLMProviders.spec(id: id)?.displayName ?? id
    }
}

struct ActionItemRow: View {
    let item: ActionItem
    let toggle: () -> Void

    private var isDone: Bool { item.done == true }

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: isDone ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(isDone ? Theme.accent : Theme.textTertiary)
                Text(item.text)
                    .font(.system(size: 14))
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? Theme.textTertiary : Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if let owner = item.owner, !owner.isEmpty {
                    Text(owner)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            item.text + (item.owner.map { ", \($0)" } ?? "") + (isDone ? ", done" : ""))
    }
}

struct MarkdownText: View {
    let markdown: String

    var body: some View {
        if let attributed = try? AttributedString(
            markdown: markdown,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))
        {
            Text(attributed).textSelection(.enabled)
        } else {
            Text(markdown).textSelection(.enabled)
        }
    }
}
