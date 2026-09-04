import SwiftUI

struct MeetingDetailView: View {
    @Environment(AppState.self) private var app
    @State private var meeting: Meeting
    @State private var tab: Tab = .notes
    @State private var segments: [TranscriptSegment] = []
    @State private var saveTask: Task<Void, Never>?
    @State private var renamingSpeaker: String?
    @State private var renameSpeakerTo = ""

    private var isEnhancing: Bool {
        app.enhancingMeetingIDs.contains(meeting.id)
    }

    enum Tab: String, CaseIterable {
        case notes = "Notes"
        case enhanced = "Enhanced"
        case transcript = "Transcript"
    }

    init(meeting: Meeting) {
        _meeting = State(initialValue: meeting)
        // A recorded meeting centers the transcript; a quick note centers the editor.
        if meeting.audioMicPath != nil || meeting.status == .recording {
            _tab = State(initialValue: .transcript)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            switch tab {
            case .notes:
                notesEditor
            case .enhanced:
                EnhancedNotesView(meetingID: meeting.id)
            case .transcript:
                transcriptList
            }
        }
        .task(id: liveTranscription == nil) { await loadSegments() }
        .alert("Rename speaker", isPresented: .constant(renamingSpeaker != nil)) {
            TextField("Name", text: $renameSpeakerTo)
            Button("Rename") {
                if let from = renamingSpeaker, let db = app.database {
                    let to = renameSpeakerTo.trimmingCharacters(in: .whitespaces)
                    if !to.isEmpty, to != from {
                        try? db.renameSpeaker(meetingID: meeting.id, from: from, to: to)
                        Task { await loadSegments() }
                    }
                }
                renamingSpeaker = nil
            }
            Button("Cancel", role: .cancel) { renamingSpeaker = nil }
        } message: {
            Text("Applies to every line by this speaker in the meeting.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    app.selectedMeetingID = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 6)

                Text(meeting.createdAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)

                if meeting.language != "auto" {
                    Text(String(meeting.language.prefix(2)).uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.border, in: Capsule())
                }

                if let folder = app.folders.first(where: { $0.id == meeting.folderID }) {
                    Label(folder.name, systemImage: "folder")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.fillSubtle, in: Capsule())
                }

                Spacer()

                actionsMenu
            }

            TextField("Title", text: $meeting.title)
                .font(Theme.meetingTitleFont)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .onChange(of: meeting.title) { scheduleSave() }

            RecordingBar(meeting: meeting)

            tabBar
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, 0)
    }

    private var folderSection: some View {
        Menu("Move to folder") {
            Button("No folder") {
                meeting.folderID = nil
                scheduleSave()
            }
            ForEach(app.folders) { folder in
                Button(folder.team.map { "\($0) / \(folder.name)" } ?? folder.name) {
                    meeting.folderID = folder.id
                    scheduleSave()
                }
            }
        }
    }

    private var templateSection: some View {
        Menu("Template") {
            Button("Default template") {
                meeting.templateID = nil
                scheduleSave()
            }
            ForEach(app.templates) { template in
                Button(template.name) {
                    meeting.templateID = template.id
                    scheduleSave()
                }
            }
        }
    }

    private var actionsMenu: some View {
        Menu {
            folderSection
            templateSection
            Divider()
            Button("Export as Markdown…") {
                if let db = app.database {
                    MeetingExporter.exportViaSavePanel(
                        meeting: meeting, database: db,
                        folder: app.folders.first { $0.id == meeting.folderID })
                }
            }
            Button("Copy transcript") {
                if let db = app.database {
                    MeetingExporter.copyTranscript(meeting: meeting, database: db)
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var tabBar: some View {
        HStack(spacing: 22) {
            ForEach(Tab.allCases, id: \.self) { item in
                Button {
                    tab = item
                } label: {
                    VStack(spacing: 7) {
                        HStack(spacing: 6) {
                            Text(item.rawValue)
                                .font(.system(size: 13, weight: tab == item ? .semibold : .regular))
                                .foregroundStyle(tab == item ? Theme.textPrimary : Theme.textSecondary)
                            if item == .enhanced, isEnhancing {
                                Circle()
                                    .fill(Theme.statusProcessing)
                                    .frame(width: 5, height: 5)
                            }
                        }
                        Rectangle()
                            .fill(tab == item ? Theme.accent : .clear)
                            .frame(height: 2)
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Notes

    private var notesEditor: some View {
        TextEditor(text: $meeting.notesMarkdown)
            .font(.system(size: 14))
            .lineSpacing(3)
            .foregroundStyle(Theme.textPrimary)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
            .onChange(of: meeting.notesMarkdown) { scheduleSave() }
            .overlay(alignment: .topLeading) {
                if meeting.notesMarkdown.isEmpty {
                    Text("Type your rough notes here — the AI will expand them after the meeting.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
    }

    // MARK: - Transcript

    private var liveTranscription: TranscriptionCoordinator? {
        guard let coordinator = app.transcription, coordinator.meetingID == meeting.id else {
            return nil
        }
        return coordinator
    }

    private var transcriptList: some View {
        let live = liveTranscription
        let shown = live.map(\.liveSegments) ?? segments
        return Group {
            if let live, shown.isEmpty, case .failed(let message) = live.phase {
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
                    Button("Retry") { live.retryIfFailed() }
                        .buttonStyle(.bordered)
                        .tint(.white)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.isEmpty && live == nil {
                VStack(spacing: 10) {
                    Image(systemName: "text.quote")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.textTertiary)
                    Text("No transcript")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("The transcript will appear here once a recording exists.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(shown) { segment in
                                SegmentRow(segment: segment)
                                    .id(segment.id)
                                    .contextMenu {
                                        if live == nil {
                                            Button("Rename \"\(segment.speaker)\"…") {
                                                renameSpeakerTo = segment.speaker
                                                renamingSpeaker = segment.speaker
                                            }
                                        }
                                    }
                            }
                            // Volatile (in-flight) text stays in the HUD and captions
                            // overlay; observing it here re-evaluated this whole list
                            // at the volatile flush rate and stalled Record.
                        }
                        .padding(.horizontal, 28)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: shown.count) {
                        if let last = shown.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private func loadSegments() async {
        guard let db = app.database else { return }
        let meetingID = meeting.id
        let loaded = await Task.detached(priority: .userInitiated) {
            (try? db.fetchSegments(meetingID: meetingID)) ?? []
        }.value
        guard !Task.isCancelled else { return }
        segments = loaded
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = meeting
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            app.update(snapshot)
        }
    }
}

struct SegmentRow: View {
    let segment: TranscriptSegment

    private static let palette: [Color] = [.orange, .purple, .teal, .pink, .indigo, .mint]

    private var speakerColor: Color {
        if segment.channel == .mic { return Theme.channelMe }
        if segment.speaker == "Them" { return Theme.accent }
        let hash = segment.speaker.unicodeScalars.reduce(0) {
            ($0 &* 31 &+ Int($1.value)) & 0x7FFF_FFFF
        }
        return Self.palette[hash % Self.palette.count]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text(segment.speaker)
                    .font(Theme.fontCaption.weight(.semibold))
                    .foregroundStyle(speakerColor)
                Text(Self.timestamp(segment.startSeconds))
                    .font(Theme.fontSmall)
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            Text(segment.text)
                .font(.system(size: 15))
                .lineSpacing(7)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    static func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
