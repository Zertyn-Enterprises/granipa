import SwiftUI

struct MeetingOverviewView: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting
    let isProcessing: Bool
    let onOpenNotes: () -> Void

    private var isEnhancing: Bool {
        app.enhancingMeetingIDs.contains(meeting.id)
    }

    private var actionItems: [ActionItem] {
        ActionItem.decodeList(from: meeting.actionItemsJSON)
    }

    private var hasAudio: Bool {
        meeting.audioMicPath != nil || meeting.audioSystemPath != nil
    }

    var body: some View {
        Group {
            if isEnhancing || isProcessing {
                VStack(spacing: 10) {
                    ProgressView()
                    Text(isEnhancing ? "Writing notes…" : "Processing this recording…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("The overview fills in when processing finishes.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spaceL) {
                        summaryCard
                        if !actionItems.isEmpty {
                            actionCard
                        }
                        if !hasAudio, meeting.summary == nil, actionItems.isEmpty {
                            EmptyStateView(
                                icon: "doc.text",
                                title: "No overview yet",
                                message: "Record or enhance to build this overview.")
                            Button("Open notes", action: onOpenNotes)
                                .buttonStyle(.bordered)
                                .tint(.white)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private var summaryCard: some View {
        let summary = meeting.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Summary", systemImage: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                enhanceButton(title: summary.isEmpty ? "Enhance now" : "Re-enhance")
            }
            if summary.isEmpty {
                Text("No summary yet")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textTertiary)
            } else {
                MarkdownText(markdown: summary)
                    .font(.system(size: 14))
                    .lineSpacing(5)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
    }

    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Action items")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            VStack(alignment: .leading, spacing: 7) {
                ForEach(Array(actionItems.enumerated()), id: \.offset) { index, item in
                    ActionItemRow(item: item) {
                        app.toggleActionItem(meetingID: meeting.id, index: index)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
    }

    private func enhanceButton(title: String) -> some View {
        Button {
            Task { await app.enhance(meetingID: meeting.id) }
        } label: {
            Label(title, systemImage: "wand.and.stars")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.bordered)
        .tint(.white)
        .controlSize(.small)
        .disabled(isEnhancing || app.recorder.meetingID == meeting.id)
        .accessibilityLabel(title == "Re-enhance" ? "Regenerate summary" : "Enhance now")
    }
}

struct MeetingActionItemsView: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting

    private var items: [ActionItem] {
        ActionItem.decodeList(from: meeting.actionItemsJSON)
    }

    var body: some View {
        if items.isEmpty {
            EmptyStateView(
                icon: "checklist",
                title: "No action items",
                message: "Action items appear here after enhancement.")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                        ActionItemRow(item: item) {
                            app.toggleActionItem(meetingID: meeting.id, index: index)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Theme.card,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct MeetingTranscriptView: View {
    let segments: [TranscriptSegment]
    let live: TranscriptionCoordinator?
    let isProcessing: Bool
    @Bindable var playback: MeetingPlaybackController
    @Binding var autoscroll: Bool
    @Binding var selectedID: String?
    @Binding var search: String
    @Binding var speakerFilter: String?
    let onRename: (String) -> Void

    @FocusState private var searchFocused: Bool
    @State private var talkReport: SpeakerTalkTime.Report?

    private var shown: [TranscriptSegment] {
        live.map(\.liveSegments) ?? segments
    }

    private var filtered: [TranscriptSegment] {
        TranscriptQuery.filter(segments: shown, query: search, speaker: speakerFilter)
    }

    private var speakers: [String] {
        TranscriptQuery.speakers(in: shown)
    }

    private var currentIDs: Set<String> {
        Set(TranscriptQuery.containing(shown, at: playback.currentTime).map(\.id))
    }

    private var canPlay: Bool {
        switch playback.state {
        case .ready, .playing, .paused, .ended: true
        case .idle, .failed: false
        }
    }

    var body: some View {
        Group {
            if let live, shown.isEmpty, case .failed(let message) = live.phase {
                failed(message: message, retry: { live.retryIfFailed() })
            } else if shown.isEmpty, live == nil, isProcessing {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Processing this recording…")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("The transcript and AI notes appear when processing finishes.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty && live == nil {
                EmptyStateView(
                    icon: "text.quote",
                    title: "No transcript",
                    message: "The transcript will appear here once a recording exists.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                populated
            }
        }
        .task(id: shown) {
            let source = shown
            let report = await Task.detached(priority: .utility) {
                SpeakerTalkTime.report(segments: source)
            }.value
            guard !Task.isCancelled else { return }
            talkReport = report
        }
    }

    private var populated: some View {
        VStack(spacing: 0) {
            toolbar
            Rectangle().fill(Theme.border).frame(height: 1)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(filtered) { segment in
                            SegmentRow(
                                segment: segment,
                                isCurrent: currentIDs.contains(segment.id),
                                isSelected: selectedID == segment.id,
                                onPlay: canPlay
                                    ? {
                                        selectedID = segment.id
                                        playback.seek(to: segment.startSeconds)
                                        playback.play()
                                    } : nil,
                                onSelect: {
                                    selectedID = segment.id
                                    if canPlay {
                                        playback.seek(to: segment.startSeconds)
                                    }
                                }
                            )
                            .id(segment.id)
                            .contextMenu {
                                if live == nil {
                                    Button("Rename \"\(segment.speaker)\"…") {
                                        onRename(segment.speaker)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: playback.currentTime) {
                    guard autoscroll else { return }
                    if let id = TranscriptQuery.containing(filtered, at: playback.currentTime)
                        .first?.id
                    {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
                .onChange(of: filtered.count) {
                    guard autoscroll, let last = filtered.last else { return }
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            talkStrip
            footer
        }
        .background {
            Button("Search transcript") { searchFocused = true }
                .keyboardShortcut("f", modifiers: .command)
                .hidden()
                .accessibilityHidden(true)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textTertiary)
                TextField("Search transcript", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textPrimary)
                    .focused($searchFocused)
                    .accessibilityLabel("Search transcript")
                if !search.isEmpty {
                    Button {
                        search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
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

            speakerMenu
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 10)
    }

    private var speakerMenu: some View {
        Menu {
            Picker("Speakers", selection: $speakerFilter) {
                Text("All speakers").tag(String?.none)
                ForEach(speakers, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.2")
                    .font(.system(size: 11.5))
                Text(speakerFilter ?? "All speakers")
                    .lineLimit(1)
            }
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(speakerFilter == nil ? Theme.textSecondary : Theme.accent)
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
        .disabled(speakers.isEmpty)
        .accessibilityLabel("Filter speakers")
        .help("Filter speakers")
    }

    @ViewBuilder
    private var talkStrip: some View {
        if let report = talkReport, !report.rows.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        ForEach(report.rows, id: \.speaker) { row in
                            Rectangle()
                                .fill(Theme.avatarColor(for: row.speaker))
                                .frame(width: max(2, geo.size.width * row.share))
                        }
                    }
                }
                .frame(height: 6)
                .clipShape(Capsule())
                .accessibilityHidden(true)

                ForEach(report.rows, id: \.speaker) { row in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Theme.avatarColor(for: row.speaker))
                            .frame(width: 7, height: 7)
                        Text(row.speaker)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(LiveStageFormat.elapsed(Int(row.seconds.rounded(.down))))
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                        Text("\(Int((row.share * 100).rounded()))%")
                            .foregroundStyle(Theme.textTertiary)
                            .monospacedDigit()
                    }
                    .font(.system(size: 11.5))
                    .accessibilityLabel(
                        "\(row.speaker) \(Int((row.share * 100).rounded())) percent")
                }
                if report.hasOverlap {
                    Text("Overlapping speech is counted for each speaker.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
        }
    }

    private var footer: some View {
        HStack {
            Text(resultLabel)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            Spacer()
            Toggle("Auto-scroll", isOn: $autoscroll)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityLabel("Auto-scroll")
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }

    private var resultLabel: String {
        let needle = TranscriptQuery.normalizedQuery(search)
        if needle.isEmpty, speakerFilter == nil {
            return "\(filtered.count) lines"
        }
        return "\(filtered.count) results"
    }

    private func failed(message: String, retry: @escaping () -> Void) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "xmark.circle")
                .font(.system(size: 28))
                .foregroundStyle(Theme.statusFailed)
            Text("Transcription failed")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .tint(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SegmentRow: View {
    let segment: TranscriptSegment
    var isCurrent = false
    var isSelected = false
    var onPlay: (() -> Void)? = nil
    var onSelect: (() -> Void)? = nil

    private static let palette: [Color] = [.orange, .purple, .teal, .pink, .indigo, .mint]

    private var speakerColor: Color {
        if segment.channel == .mic { return Theme.channelMe }
        if segment.speaker == "Them" { return Theme.accent }
        let hash = segment.speaker.unicodeScalars.reduce(0) {
            ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF
        }
        return Self.palette[hash % Self.palette.count]
    }

    private var usesRecordedChrome: Bool {
        onPlay != nil || onSelect != nil || isCurrent || isSelected
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if let onPlay {
                Button(action: onPlay) {
                    Image(systemName: isCurrent ? "play.circle.fill" : "play.circle")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(
                            isCurrent || isSelected ? Theme.accent : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Play from \(LiveStageFormat.elapsed(Int(segment.startSeconds)))")
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    if usesRecordedChrome {
                        AvatarView(letterSource: segment.speaker, size: 18)
                    }
                    Text(segment.speaker)
                        .font(Theme.fontCaption.weight(.semibold))
                        .foregroundStyle(speakerColor)
                    Text(LiveStageFormat.elapsed(Int(segment.startSeconds.rounded(.down))))
                        .font(Theme.fontSmall)
                        .foregroundStyle(Theme.textTertiary)
                        .monospacedDigit()
                }
                Text(segment.text)
                    .font(.system(size: 15))
                    .lineSpacing(7)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            (isCurrent || isSelected) ? Theme.accent.opacity(0.08) : Theme.card,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            if usesRecordedChrome {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        (isCurrent || isSelected) ? Theme.accent : Theme.border, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect?() }
    }
}
