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
                        .foregroundStyle(Theme.statusListening)
                    if let started = app.recorder.startedAt {
                        RecordingTimer(startedAt: started)
                            .font(.system(size: 13, weight: .medium).monospacedDigit())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    LevelMeter(label: "Mic", level: app.recorder.micLevel)
                    LevelMeter(label: "System", level: app.recorder.systemLevel)
                    Spacer()
                    Button("Stop", systemImage: "stop.fill") {
                        Task { await app.stopRecording() }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.statusListening)
                    .controlSize(.small)
                    .accessibilityLabel("Stop recording")
                } else {
                    Button {
                        app.startRecording(meetingID: meeting.id)
                    } label: {
                        Label("Record", systemImage: "record.circle")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .granipaPrimaryControl()
                    .disabled(app.recorder.isBusy)
                    Spacer()
                }
            }
            if isRecordingThisMeeting, let warning = app.recorder.systemAudioWarning {
                AudioWarningLabel(text: warning)
            }
            if isRecordingThisMeeting, let warning = app.recorder.micWarning {
                AudioWarningLabel(text: warning, icon: "mic.slash")
            }
            if isRecordingThisMeeting, let transcription = app.transcription {
                switch transcription.phase {
                case .preparing:
                    Label("Preparing speech model…", systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    TranscriptionFailedLabel(message: message) {
                        app.transcription?.retryIfFailed()
                    }
                default:
                    EmptyView()
                }
            }
        }
    }
}

struct LevelMeter: View {
    let label: String
    let level: Float

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.fillSubtle)
                Capsule()
                    .fill(Theme.statusDone)
                    .frame(width: CGFloat(min(level * 300, 60)))
            }
            .frame(width: 60, height: 6)
        }
    }
}
