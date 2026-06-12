import SwiftUI

struct RecordingHUD: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hudCompact") private var compact = false

    private var meetingTitle: String {
        guard let id = app.recorder.meetingID else { return "" }
        return app.meetings.first { $0.id == id }?.title ?? ""
    }

    private var transcriptionFailed: Bool {
        if case .failed = app.transcription?.phase { return true }
        return false
    }

    var body: some View {
        Group {
            if app.recorder.isRecording {
                if compact {
                    compactPill
                } else {
                    expandedCard
                }
            } else {
                VStack(spacing: 8) {
                    Text("Not recording")
                        .foregroundStyle(.secondary)
                    Button("Close") { dismiss() }
                }
                .padding(16)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .preferredColorScheme(.dark)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 6)
        .padding(8)
    }

    private var compactPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "record.circle.fill")
                .font(.system(size: 13))
                .foregroundStyle(transcriptionFailed ? .orange : .red)
                .symbolEffect(.pulse)
            if let started = app.recorder.startedAt {
                TimelineView(.periodic(from: started, by: 1)) { context in
                    Text(elapsed(from: started, to: context.date))
                        .monospacedDigit()
                        .font(.caption)
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            HStack(spacing: 5) {
                ActivityDot(level: app.recorder.micLevel)
                ActivityDot(level: app.recorder.systemLevel)
            }
            Button {
                Task { await app.stopRecording() }
                dismiss()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
            .help("Stop recording")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture { compact = false }
        .help("Click to expand")
    }

    private var expandedCard: some View {
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
                Button {
                    compact = true
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Shrink to pill")
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
                switch live.phase {
                case .preparing:
                    Label(
                        "Preparing the speech model — the first recording on this Mac downloads it, which can take a few minutes.",
                        systemImage: "arrow.down.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    Label("Transcription failed: \(message)", systemImage: "xmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                default:
                    VStack(alignment: .leading, spacing: 2) {
                        if let last = live.liveSegments.last {
                            Text("\(last.speaker): \(last.text)")
                                .font(.caption)
                                .lineLimit(2)
                                .truncationMode(.head)
                                .foregroundStyle(.secondary)
                        }
                        if !live.volatileSystem.isEmpty {
                            Text("Them: \(live.volatileSystem)")
                                .font(.caption)
                                .lineLimit(2)
                                .truncationMode(.head)
                                .italic()
                                .foregroundStyle(.tertiary)
                        } else if !live.volatileMic.isEmpty {
                            Text("Me: \(live.volatileMic)")
                                .font(.caption)
                                .lineLimit(2)
                                .truncationMode(.head)
                                .italic()
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(16)
        .frame(width: 400)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.12), lineWidth: 1))
    }

    private func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

private struct ActivityDot: View {
    let level: Float

    var body: some View {
        Circle()
            .fill(.green)
            .frame(width: 5, height: 5)
            .opacity(0.25 + Double(min(level * 6, 0.75)))
            .animation(.linear(duration: 0.1), value: level)
    }
}
