import SwiftUI

struct MeetingDetailView: View {
    @Environment(AppState.self) private var app
    @State private var meeting: Meeting
    @State private var tab: Tab = .notes
    @State private var segments: [TranscriptSegment] = []
    @State private var saveTask: Task<Void, Never>?

    enum Tab: String, CaseIterable {
        case notes = "Notes"
        case enhanced = "Enhanced"
        case transcript = "Transcript"
    }

    init(meeting: Meeting) {
        _meeting = State(initialValue: meeting)
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
        .task { loadSegments() }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                    Text(meeting.language.hasPrefix("es") ? "ES" : "EN")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.07), in: Capsule())
                }

                Spacer()

                folderMenu
                templateMenu
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
        .padding(.top, 18)
        .padding(.bottom, 0)
    }

    private var folderMenu: some View {
        Menu {
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
        } label: {
            Label(
                app.folders.first { $0.id == meeting.folderID }?.name ?? "No folder",
                systemImage: "folder")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var templateMenu: some View {
        Menu {
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
        } label: {
            Label(
                app.templates.first { $0.id == meeting.templateID }?.name ?? "Template",
                systemImage: "doc.text")
                .font(.system(size: 12))
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
                        Text(item.rawValue)
                            .font(.system(size: 13, weight: tab == item ? .semibold : .regular))
                            .foregroundStyle(tab == item ? Theme.textPrimary : Theme.textSecondary)
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
            if shown.isEmpty && live == nil {
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
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(shown) { segment in
                                SegmentRow(segment: segment)
                                    .id(segment.id)
                            }
                            if let live {
                                if !live.volatileMic.isEmpty {
                                    VolatileRow(speaker: "Me", text: live.volatileMic)
                                        .id("volatile-mic")
                                }
                                if !live.volatileSystem.isEmpty {
                                    VolatileRow(speaker: "Them", text: live.volatileSystem)
                                        .id("volatile-system")
                                }
                            }
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
                    .onChange(of: (live?.volatileMic ?? "") + "|" + (live?.volatileSystem ?? "")) {
                        if live?.volatileSystem.isEmpty == false {
                            proxy.scrollTo("volatile-system", anchor: .bottom)
                        } else if live?.volatileMic.isEmpty == false {
                            proxy.scrollTo("volatile-mic", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .onChange(of: app.transcription == nil) {
            loadSegments()
        }
    }

    private func loadSegments() {
        guard let db = app.database else { return }
        segments = (try? db.fetchSegments(meetingID: meeting.id)) ?? []
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
        if segment.channel == .mic { return Color(hex: 0x6FA8DC) }
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
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(speakerColor)
                Text(Self.timestamp(segment.startSeconds))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            Text(segment.text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
    }

    static func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct VolatileRow: View {
    let speaker: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(speaker)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(.system(size: 14))
                .lineSpacing(3)
                .italic()
                .foregroundStyle(Theme.textSecondary)
        }
    }
}
