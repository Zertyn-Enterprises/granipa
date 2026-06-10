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

    private var transcriptList: some View {
        Group {
            if segments.isEmpty {
                ContentUnavailableView(
                    "No transcript",
                    systemImage: "text.quote",
                    description: Text("The transcript will appear here once a recording exists.")
                )
            } else {
                List(segments) { segment in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(segment.speaker)
                                .font(.caption.bold())
                                .foregroundStyle(segment.channel == .mic ? .blue : .orange)
                            Text(timestamp(segment.startSeconds))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(segment.text)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func timestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
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
