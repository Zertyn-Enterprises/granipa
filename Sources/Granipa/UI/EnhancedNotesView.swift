import SwiftUI

struct EnhancedNotesView: View {
    @Environment(AppState.self) private var app
    let meetingID: String

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
            } else if let meeting, meeting.enhancedNotesMarkdown != nil {
                content(for: meeting)
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

    private func content(for meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if let summary = meeting.summary, !summary.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        MarkdownText(markdown: summary)
                            .font(.system(size: 14))
                            .lineSpacing(5)
                            .foregroundStyle(Theme.textSecondary)
                        Rectangle()
                            .fill(Theme.border)
                            .frame(height: 1)
                    }
                }

                if let notes = meeting.enhancedNotesMarkdown {
                    MarkdownBlocksView(markdown: notes)
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
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.horizontal, 32)
            .padding(.vertical, 26)
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 17, weight: .semibold, design: .serif))
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

private struct ActionItemRow: View {
    let item: ActionItem
    let toggle: () -> Void

    private var isDone: Bool { item.done == true }

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: isDone ? "checkmark.square.fill" : "square")
                    .font(.system(size: 14))
                    .foregroundStyle(isDone ? Theme.accent : Theme.textTertiary)
                Text(item.text + (item.owner.map { " — \($0)" } ?? ""))
                    .font(.system(size: 14))
                    .strikethrough(isDone)
                    .foregroundStyle(isDone ? Theme.textTertiary : Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
