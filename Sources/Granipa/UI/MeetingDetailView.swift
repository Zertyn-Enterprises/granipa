import SwiftUI

enum MeetingHeaderMeta {
    struct Item: Equatable {
        var text: String
        var systemImage: String
    }

    static func items(
        createdAt: Date,
        startedAt: Date?,
        endedAt: Date?,
        language: String,
        folderName: String?,
        phase: MeetingPipelinePhase,
        hasAudio: Bool
    ) -> [Item] {
        var result: [Item] = [
            Item(text: dateText(createdAt: createdAt, startedAt: startedAt, endedAt: endedAt),
                 systemImage: "calendar")
        ]
        if let duration = MeetingLibrary.durationLabel(from: startedAt, to: endedAt) {
            result.append(Item(text: duration, systemImage: "clock"))
        }
        if language != "auto" {
            result.append(
                Item(
                    text: String(language.prefix(2)).uppercased(),
                    systemImage: "globe"))
        }
        if let folderName, !folderName.isEmpty {
            result.append(Item(text: folderName, systemImage: "folder"))
        }
        if phase.isLive {
            result.append(Item(text: phase.label, systemImage: phase.systemImage))
        } else if hasAudio {
            result.append(Item(text: "Recorded", systemImage: "checkmark.circle.fill"))
        }
        return result
    }

    static func dateText(createdAt: Date, startedAt: Date?, endedAt: Date?) -> String {
        if let startedAt, let endedAt {
            let day = startedAt.formatted(.dateTime.month(.abbreviated).day().year())
            let from = startedAt.formatted(.dateTime.hour().minute())
            let to = endedAt.formatted(.dateTime.hour().minute())
            return "\(day) · \(from) – \(to)"
        }
        let start = startedAt ?? createdAt
        return start.formatted(.dateTime.weekday(.wide).month().day().hour().minute())
    }
}

enum MeetingTabAccessory {
    static func actionItemCountLabel(_ count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }
}

struct MeetingDetailView: View {
    @Environment(AppState.self) private var app
    @State private var meeting: Meeting
    @State private var tab: Tab
    @State private var transcript = MeetingTranscriptModel()
    @State private var enhancedDocument = EnhancedNotesDocument()
    @State private var saveTask: Task<Void, Never>?
    @State private var renamingSpeaker: String?
    @State private var renameSpeakerTo = ""
    @State private var playback = MeetingPlaybackController()
    @State private var autoscroll = false
    @State private var selectedSegmentID: String?
    @State private var transcriptSearch = ""
    @State private var speakerFilter: String?
    @State private var confirmDelete = false
    @FocusState private var notesFocused: Bool
    @State private var quickNoteScrolls = 0

    private var isEnhancing: Bool {
        app.enhancingMeetingIDs.contains(meeting.id)
    }

    private var isLiveStage: Bool {
        app.recorder.isBusy && app.recorder.meetingID == meeting.id
    }

    private var actionItemCount: Int {
        ActionItem.decodeList(from: freshMeeting.actionItemsJSON).count
    }

    private var freshMeeting: Meeting {
        app.meetings.first { $0.id == meeting.id } ?? meeting
    }

    enum Tab: String, CaseIterable {
        case overview = "Overview"
        case enhanced = "AI Notes"
        case transcript = "Transcript"
        case actionItems = "Action Items"
        case notes = "Notes"
    }

    init(meeting: Meeting, preferNotes: Bool = false) {
        _meeting = State(initialValue: meeting)
        _tab = State(initialValue: Self.initialTab(preferNotes: preferNotes))
    }

    /// Landing tab when someone opens a meeting from the library. Everything
    /// starts on Overview; only the Notes library routes straight to Notes.
    /// Meeting fields no longer matter: audio/no-audio both land on Overview,
    /// and while a recording is live the stage replaces tab content anyway.
    static func initialTab(preferNotes: Bool) -> Tab {
        preferNotes ? .notes : .overview
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.border).frame(height: 1)
            if isLiveStage {
                liveContent
            } else {
                switch tab {
                case .overview:
                    MeetingOverviewView(
                        meeting: freshMeeting,
                        isProcessing: isPostStopProcessing,
                        onOpenNotes: { tab = .notes },
                        onOpenEnhanced: { tab = .enhanced },
                        onOpenActionItems: { tab = .actionItems })
                case .enhanced:
                    EnhancedNotesView(meetingID: meeting.id, document: enhancedDocument)
                case .transcript:
                    MeetingTranscriptView(
                        segments: transcript.segments,
                        loadPhase: transcript.phase,
                        live: liveTranscription,
                        isProcessing: isPostStopProcessing,
                        playback: playback,
                        autoscroll: $autoscroll,
                        selectedID: $selectedSegmentID,
                        search: $transcriptSearch,
                        speakerFilter: $speakerFilter,
                        onRename: { speaker in
                            renameSpeakerTo = speaker
                            renamingSpeaker = speaker
                        },
                        onRetry: { loadSegments() })
                case .actionItems:
                    MeetingActionItemsView(meeting: freshMeeting)
                case .notes:
                    notesEditor
                }
            }
        }
        .task(id: taskKey) { loadSegments() }
        .task(id: audioPathsKey) { reloadPlayback() }
        .onChange(of: transcript.phase) { _, phase in
            guard case .loaded = phase else { return }
            speakerFilter = TranscriptQuery.retainedSpeakerFilter(
                speakerFilter, in: transcript.segments)
        }
        .onChange(of: app.recorder.isBusy) { _, busy in
            if busy { playback.stopAndRelease() }
            else { reloadPlayback() }
        }
        .onChange(of: app.dictation.phase.isActive) { _, active in
            if active {
                playback.stopAndRelease()
            } else if !isLiveStage {
                reloadPlayback()
            }
        }
        .onDisappear { playback.stopAndRelease() }
        .alert("Rename speaker", isPresented: .constant(renamingSpeaker != nil)) {
            TextField("Name", text: $renameSpeakerTo)
            Button("Rename") {
                if let from = renamingSpeaker, let db = app.database {
                    let to = renameSpeakerTo.trimmingCharacters(in: .whitespaces)
                    if !to.isEmpty, to != from {
                        try? db.renameSpeaker(meetingID: meeting.id, from: from, to: to)
                        speakerFilter = TranscriptQuery.remappedSpeakerFilter(
                            speakerFilter, from: from, to: to)
                        loadSegments()
                    }
                }
                renamingSpeaker = nil
            }
            Button("Cancel", role: .cancel) { renamingSpeaker = nil }
        } message: {
            Text("Applies to every line by this speaker in the meeting.")
        }
        .alert("Delete this meeting?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { app.deleteMeeting(id: meeting.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recording, transcript, and notes will be removed.")
        }
    }

    // MARK: - Header

    private var backLabel: String {
        AppNavigation.resolvedAppDestination(app.sidebarDestination) == .home
            ? "Back to Home" : "Back"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button {
                    app.selectedMeetingID = nil
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 13, weight: .semibold))
                        Text(backLabel)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 6)
                .accessibilityLabel(backLabel)

                Spacer(minLength: 8)

                Button {
                    if let db = app.database {
                        MeetingExporter.exportViaSavePanel(
                            meeting: freshMeeting, database: db,
                            folder: app.folders.first { $0.id == meeting.folderID })
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .hoverHighlight(cornerRadius: 6)
                .help("Export as Markdown")
                .accessibilityLabel("Export as Markdown")

                actionsMenu
            }

            TextField("Title", text: $meeting.title, axis: .vertical)
                .font(Theme.meetingTitleFont)
                .foregroundStyle(Theme.textPrimary)
                .textFieldStyle(.plain)
                .lineLimit(1...3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Meeting title")
                .onChange(of: meeting.title) { scheduleSave() }

            metadataRow

            if !isLiveStage {
                MeetingPlaybackBar(playback: playback, meeting: freshMeeting)
                tabBar
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 14)
        .padding(.bottom, isLiveStage ? 14 : 0)
    }

    private var metadataRow: some View {
        let folderName = app.folders.first { $0.id == meeting.folderID }?.name
        let chips = MeetingHeaderMeta.items(
            createdAt: meeting.createdAt,
            startedAt: freshMeeting.startedAt,
            endedAt: freshMeeting.endedAt,
            language: meeting.language,
            folderName: folderName,
            phase: app.pipelinePhase(for: freshMeeting),
            hasAudio: freshMeeting.audioMicPath != nil || freshMeeting.audioSystemPath != nil)
        return ViewThatFits(in: .horizontal) {
            chipsRow(chips)
            ScrollView(.horizontal, showsIndicators: false) {
                chipsRow(chips)
            }
        }
    }

    private func chipsRow(_ chips: [MeetingHeaderMeta.Item]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, item in
                metaChip(item)
            }
        }
    }

    private func metaChip(_ item: MeetingHeaderMeta.Item) -> some View {
        let phase = app.pipelinePhase(for: freshMeeting)
        let isRecorded = item.text == "Recorded"
        let isLive = phase.isLive && item.text == phase.label
        let color: Color = {
            if isRecorded { return Theme.statusDone }
            if isLive { return phase.color }
            return Theme.textSecondary
        }()
        return Label(item.text, systemImage: item.systemImage)
            .font(.system(size: 11, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                isRecorded || isLive ? color.opacity(0.14) : Theme.fillSubtle,
                in: Capsule())
            .lineLimit(1)
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
                        meeting: freshMeeting, database: db,
                        folder: app.folders.first { $0.id == meeting.folderID })
                }
            }
            .accessibilityLabel("Export as Markdown")
            Button("Copy transcript") {
                if let db = app.database {
                    MeetingExporter.copyTranscript(meeting: freshMeeting, database: db)
                }
            }
            if let draft = freshMeeting.emailDraft, !draft.isEmpty {
                Button("Copy email") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(draft, forType: .string)
                    ToastController.shared.show("Email copied")
                }
            }
            Divider()
            Button("Delete meeting", role: .destructive) {
                confirmDelete = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Meeting actions")
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(Tab.allCases, id: \.self) { item in
                    Button {
                        tab = item
                    } label: {
                        VStack(spacing: 0) {
                            HStack(spacing: 6) {
                                Text(item.rawValue)
                                    .font(.system(size: 13, weight: tab == item ? .semibold : .regular))
                                    .foregroundStyle(
                                        tab == item ? Theme.textPrimary : Theme.textSecondary)
                                if item == .enhanced, isEnhancing {
                                    Circle()
                                        .fill(Theme.statusProcessing)
                                        .frame(width: 5, height: 5)
                                }
                                if item == .actionItems,
                                    let count = MeetingTabAccessory.actionItemCountLabel(
                                        actionItemCount)
                                {
                                    Text(count)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(
                                            tab == item ? Theme.accent : Theme.textTertiary)
                                        .accessibilityLabel("Action Items, \(count)")
                                }
                            }
                            .padding(.bottom, 8)
                            Rectangle()
                                .fill(tab == item ? Theme.accent : .clear)
                                .frame(height: 2)
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.rawValue)
                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                }
            }
            .padding(.top, 6)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Live stage

    /// Scroll anchor for Quick note: in the stacked layout the notes card
    /// sits under the stage, so focusing the editor must also bring it onscreen.
    private var liveHasTranscript: Bool {
        guard let live = liveTranscription else { return false }
        let state = LiveStage.state(
            isRecording: app.recorder.isRecording,
            isStarting: app.recorder.isStarting,
            transcriptionPhase: live.phase)
        guard let state, state.isCapturing else { return false }
        if case .failed = live.phase { return false }
        return true
    }

    private var liveContent: some View {
        GeometryReader { proxy in
            let arrangement = LiveStageLayout.arrangement(
                width: proxy.size.width, hasTranscript: liveHasTranscript)
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.spaceL) {
                        LiveRecordingView(meeting: meeting, quickNote: focusQuickNote)
                            .frame(maxWidth: .infinity)
                        switch arrangement {
                        case .notesBesideTranscript:
                            HStack(alignment: .top, spacing: Theme.spaceL) {
                                if let live = liveTranscription, liveHasTranscript {
                                    LiveTranscriptPanel(live: live)
                                }
                                liveNotesCard
                                    .frame(minWidth: 280, maxWidth: 400)
                            }
                        case .stacked:
                            if let live = liveTranscription, liveHasTranscript {
                                LiveTranscriptPanel(live: live)
                            }
                            liveNotesCard
                        }
                    }
                    .padding(Theme.spaceXL)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: quickNoteScrolls) { _, _ in
                    // Deliberately unanimated so Reduce Motion gets a step
                    // change instead of a scroll.
                    scrollProxy.scrollTo(LiveNotesAnchor.cardID, anchor: .top)
                }
            }
        }
    }

    private func focusQuickNote() {
        notesFocused = true
        // Counter, not the focus flag: ⌘N while already focused must re-scroll.
        quickNoteScrolls += 1
    }

    private var liveNotesCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("Meeting notes", systemImage: "square.and.pencil")
                .font(Theme.fontCaption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Theme.spaceL)
                .padding(.top, Theme.spaceL)
                .padding(.bottom, 8)
            notesTextEditor
                .padding(.horizontal, Theme.spaceL)
                .padding(.bottom, Theme.spaceL)
                .frame(height: 260)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .id(LiveNotesAnchor.cardID)
        .card(cornerRadius: Theme.radiusL)
    }

    // MARK: - Notes

    private var notesTextEditor: some View {
        TextEditor(text: $meeting.notesMarkdown)
            .font(.system(size: 14))
            .lineSpacing(3)
            .foregroundStyle(Theme.textPrimary)
            .scrollContentBackground(.hidden)
            .focused($notesFocused)
            .onChange(of: meeting.notesMarkdown) { scheduleSave() }
            .overlay(alignment: .topLeading) {
                if meeting.notesMarkdown.isEmpty {
                    Text("Type your rough notes here — the AI will expand them after the meeting.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
    }

    private var notesEditor: some View {
        notesTextEditor
            .padding(.horizontal, 22)
            .padding(.vertical, 14)
    }

    // MARK: - Data

    private var liveTranscription: TranscriptionCoordinator? {
        guard let coordinator = app.transcription, coordinator.meetingID == meeting.id else {
            return nil
        }
        return coordinator
    }

    private var isPostStopProcessing: Bool {
        guard !isLiveStage else { return false }
        switch app.pipelinePhase(for: freshMeeting) {
        case .finishing, .transcribing, .enhancing: return true
        default: return false
        }
    }

    /// Reload segments when the live coordinator detaches (stop) and again
    /// when the pipeline finishes — the local copy can lag both writes.
    private var taskKey: String {
        "\(liveTranscription != nil)-\(freshStatus.rawValue)"
    }

    private var freshStatus: MeetingStatus {
        app.meetings.first { $0.id == meeting.id }?.status ?? meeting.status
    }

    private var audioPathsKey: String {
        let fresh = freshMeeting
        return "\(fresh.audioMicPath ?? "")|\(fresh.audioSystemPath ?? "")"
    }

    private func reloadPlayback() {
        guard !isLiveStage else {
            playback.stopAndRelease()
            return
        }
        let fresh = freshMeeting
        playback.load(micPath: fresh.audioMicPath, systemPath: fresh.audioSystemPath)
    }

    private func loadSegments() {
        guard let db = app.database else { return }
        let meetingID = meeting.id
        transcript.reload {
            try await Task.detached(priority: .userInitiated) {
                try db.fetchSegments(meetingID: meetingID)
            }.value
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = meeting
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            // The editor snapshot can be older than pipeline writes (stop →
            // status/endedAt/audio paths; enhance → summary/notes), so merge
            // the edited fields onto the freshest copy instead of saving the
            // snapshot whole.
            guard let current = app.meetings.first(where: { $0.id == snapshot.id }) else {
                return
            }
            app.update(Meeting.mergingEditorEdits(snapshot, into: current))
        }
    }
}

extension Meeting {
    /// Fields the detail editor owns; every other field comes from `current`
    /// so a stale editor copy never clobbers pipeline writes.
    static func mergingEditorEdits(_ edited: Meeting, into current: Meeting) -> Meeting {
        var merged = current
        merged.title = edited.title
        merged.notesMarkdown = edited.notesMarkdown
        merged.folderID = edited.folderID
        merged.templateID = edited.templateID
        return merged
    }
}
