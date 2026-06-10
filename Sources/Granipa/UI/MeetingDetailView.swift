import SwiftUI

struct MeetingDetailView: View {
    @Environment(AppState.self) private var app
    @State private var meeting: Meeting
    @State private var tab: Tab = .notes
    @State private var segments: [TranscriptSegment] = []
    @State private var saveTask: Task<Void, Never>?

    enum Tab: Hashable {
        case notes
        case transcript
    }

    init(meeting: Meeting) {
        _meeting = State(initialValue: meeting)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            switch tab {
            case .notes:
                notesEditor
            case .transcript:
                transcriptList
            }
        }
        .task { loadSegments() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Title", text: $meeting.title)
                .font(.title2.bold())
                .textFieldStyle(.plain)
                .onChange(of: meeting.title) { scheduleSave() }
            RecordingBar(meeting: meeting)
            Picker("", selection: $tab) {
                Text("Notes").tag(Tab.notes)
                Text("Transcript").tag(Tab.transcript)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 240)
        }
        .padding()
    }

    private var notesEditor: some View {
        TextEditor(text: $meeting.notesMarkdown)
            .font(.body)
            .scrollContentBackground(.hidden)
            .padding(8)
            .onChange(of: meeting.notesMarkdown) { scheduleSave() }
    }

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
                ContentUnavailableView(
                    "No transcript",
                    systemImage: "text.quote",
                    description: Text("The transcript will appear here once a recording exists.")
                )
            } else {
                ScrollViewReader { proxy in
                    List {
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
                    .onChange(of: shown.count) {
                        if let last = shown.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(segment.speaker)
                    .font(.caption.bold())
                    .foregroundStyle(segment.channel == .mic ? .blue : .orange)
                Text(Self.timestamp(segment.startSeconds))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(segment.text)
        }
        .padding(.vertical, 2)
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
        VStack(alignment: .leading, spacing: 2) {
            Text(speaker)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
                .italic()
        }
        .padding(.vertical, 2)
    }
}
