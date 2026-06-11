import SwiftUI

struct RecordingHUD: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var meetingTitle: String {
        guard let id = app.recorder.meetingID else { return "" }
        return app.meetings.first { $0.id == id }?.title ?? ""
    }

    var body: some View {
        Group {
            if app.recorder.isRecording {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "record.circle.fill")
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse)
                        Text(meetingTitle)
                            .font(.headline)
                            .lineLimit(1)
                        Spacer()
                        if let started = app.recorder.startedAt {
                            TimelineView(.periodic(from: started, by: 1)) { context in
                                Text(elapsed(from: started, to: context.date))
                                    .monospacedDigit()
                                    .font(.callout)
                            }
                        }
                    }
                    HStack(spacing: 16) {
                        LevelMeter(label: "Mic", level: app.recorder.micLevel)
                        LevelMeter(label: "System", level: app.recorder.systemLevel)
                        Spacer()
                        Button("Stop", systemImage: "stop.fill") {
                            Task { await app.stopRecording() }
                            dismiss()
                        }
                        .tint(.red)
                    }
                    if let warning = app.recorder.micWarning ?? app.recorder.systemAudioWarning {
                        Label(warning, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                    if let live = app.transcription {
                        VStack(alignment: .leading, spacing: 2) {
                            if let last = live.liveSegments.last {
                                Text("\(last.speaker): \(last.text)")
                                    .font(.caption)
                                    .lineLimit(2)
                                    .foregroundStyle(.secondary)
                            }
                            if !live.volatileSystem.isEmpty {
                                Text("Them: \(live.volatileSystem)")
                                    .font(.caption)
                                    .lineLimit(2)
                                    .italic()
                                    .foregroundStyle(.tertiary)
                            } else if !live.volatileMic.isEmpty {
                                Text("Me: \(live.volatileMic)")
                                    .font(.caption)
                                    .lineLimit(2)
                                    .italic()
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                .padding(12)
            } else {
                VStack(spacing: 8) {
                    Text("Not recording")
                        .foregroundStyle(.secondary)
                    Button("Close") { dismiss() }
                }
                .padding(12)
            }
        }
        .frame(width: 380)
        .background(Theme.card)
        .preferredColorScheme(.dark)
    }

    private func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
