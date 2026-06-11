import SwiftUI

struct RecordingBar: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting

    private var isRecordingThisMeeting: Bool {
        app.recorder.isRecording && app.recorder.meetingID == meeting.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                if isRecordingThisMeeting {
                    Image(systemName: "record.circle.fill")
                        .foregroundStyle(.red)
                        .symbolEffect(.pulse)
                    if let started = app.recorder.startedAt {
                        TimelineView(.periodic(from: started, by: 1)) { context in
                            Text(elapsed(from: started, to: context.date))
                                .monospacedDigit()
                                .font(.callout)
                        }
                    }
                    LevelMeter(label: "Mic", level: app.recorder.micLevel)
                    LevelMeter(label: "System", level: app.recorder.systemLevel)
                    Spacer()
                    Button("Stop", systemImage: "stop.fill") {
                        Task { await app.stopRecording() }
                    }
                    .tint(.red)
                } else {
                    Button("Record", systemImage: "record.circle") {
                        app.startRecording(meetingID: meeting.id)
                    }
                    .disabled(app.recorder.isRecording)
                    Spacer()
                }
            }
            if isRecordingThisMeeting, let warning = app.recorder.systemAudioWarning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if isRecordingThisMeeting, let warning = app.recorder.micWarning {
                Label(warning, systemImage: "mic.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if isRecordingThisMeeting, let transcription = app.transcription {
                switch transcription.phase {
                case .preparing:
                    Label("Preparing speech model…", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Label("Transcription failed: \(message)", systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                default:
                    EmptyView()
                }
            }
        }
    }

    private func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct LevelMeter: View {
    let label: String
    let level: Float

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(.green)
                    .frame(width: CGFloat(min(level * 300, 60)))
            }
            .frame(width: 60, height: 6)
            .animation(.linear(duration: 0.1), value: level)
        }
    }
}
