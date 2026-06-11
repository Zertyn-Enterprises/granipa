import SwiftUI

struct EnhancedNotesView: View {
    @Environment(AppState.self) private var app
    let meetingID: String

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
                ContentUnavailableView {
                    Label("No enhanced notes yet", systemImage: "wand.and.stars")
                } description: {
                    Text("Enhancement runs automatically when a recording ends, or run it now.")
                } actions: {
                    enhanceButton(title: "Enhance now")
                }
            }
        }
    }

    private func content(for meeting: Meeting) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let summary = meeting.summary {
                    section("Summary") {
                        MarkdownText(markdown: summary)
                    }
                }
                if let notes = meeting.enhancedNotesMarkdown {
                    section("Notes") {
                        MarkdownBlocksView(markdown: notes)
                    }
                }
                let items = ActionItem.decodeList(from: meeting.actionItemsJSON)
                if !items.isEmpty {
                    section("Action items") {
                        ForEach(items, id: \.self) { item in
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "checkmark.square")
                                    .foregroundStyle(.secondary)
                                Text(item.owner.map { "\(item.text) — \($0)" } ?? item.text)
                            }
                        }
                    }
                }
                if let draft = meeting.emailDraft {
                    section("Follow-up email") {
                        MarkdownText(markdown: draft)
                        Button("Copy email", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(draft, forType: .string)
                        }
                        .font(.caption)
                    }
                }
                enhanceButton(title: "Re-enhance")
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }

    private func section(_ title: String, @ViewBuilder body: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
                .tracking(0.5)
            body()
                .font(.system(size: 14))
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
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
