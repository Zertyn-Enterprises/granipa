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

    private var processingMeetingTitle: String? {
        app.processingMeetingID.flatMap { id in
            app.meetings.first { $0.id == id }?.title
        }
    }

    var body: some View {
        Group {
            if app.recorder.isRecording {
                if compact {
                    compactPill
                } else {
                    expandedCard
                }
            } else if let title = processingMeetingTitle {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape.2")
                        .foregroundStyle(Theme.statusProcessing)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Processing notes…")
                            .font(Theme.fontBody.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(title)
                            .font(Theme.fontCaption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .padding(Theme.spaceL)
                .background(
                    Theme.card,
                    in: RoundedRectangle(cornerRadius: Theme.radiusOverlay, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    Text("Not recording")
                        .foregroundStyle(.secondary)
                    Button("Close") { dismiss() }
                }
                .padding(Theme.spaceL)
                .background(
                    Theme.card,
                    in: RoundedRectangle(cornerRadius: Theme.radiusOverlay, style: .continuous))
            }
        }
        .preferredColorScheme(.dark)
        .containerBackground(.clear, for: .window)
    }

    private var compactPill: some View {
        VStack(spacing: 12) {
            if let started = app.recorder.startedAt {
                RecordingTimer(startedAt: started)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(transcriptionFailed ? .orange : Theme.textPrimary)
            }
            HStack(spacing: 6) {
                ActivityDot(level: app.recorder.micLevel)
                ActivityDot(level: app.recorder.systemLevel)
            }
            Button {
                Task { await app.stopRecording() }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.red, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Stop recording")
            Button {
                compact = false
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help("Expand")
        }
        .padding(.vertical, Theme.spaceL)
        .padding(.horizontal, Theme.spaceL)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.strokeStrong, lineWidth: 1))
        .contentShape(Capsule())
        .gesture(WindowDragGesture())
    }

    private var expandedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "record.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.statusListening)
                Text(meetingTitle)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer()
                if let started = app.recorder.startedAt {
                    RecordingTimer(startedAt: started)
                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                Button {
                    compact = true
                } label: {
                    Image(systemName: "arrow.down.right.and.arrow.up.left")
                        .font(Theme.fontCaption.weight(.semibold))
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
                }
                .controlSize(.large)
                .tint(.red)
            }
            if let warning = app.recorder.micWarning ?? app.recorder.systemAudioWarning {
                AudioWarningLabel(text: warning)
            }
            if let warning = app.transcription?.systemWarning {
                AudioWarningLabel(text: warning)
            }
            if let live = app.transcription {
                switch live.phase {
                case .preparing:
                    Label(
                        "Preparing the speech model — the first recording on this Mac downloads it, which can take a few minutes.",
                        systemImage: "arrow.down.circle")
                        .font(Theme.fontCaption)
                        .foregroundStyle(.secondary)
                case .failed(let message):
                    TranscriptionFailedLabel(message: message) {
                        app.transcription?.retryIfFailed()
                    }
                default:
                    LiveTranscriptSnippet(
                        lastSegment: live.liveSegments.last,
                        volatileSystem: live.volatileSystem,
                        volatileMic: live.volatileMic,
                        style: .hud)
                }
            } else if app.recorder.isRecording {
                Text("Transcript after you stop")
                    .font(Theme.fontCaption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(width: 520)
        .background(
            Theme.card,
            in: RoundedRectangle(cornerRadius: Theme.radiusOverlay, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusOverlay, style: .continuous)
                .stroke(Theme.strokeStrong, lineWidth: 1))
        .gesture(WindowDragGesture())
    }
}

private struct ActivityDot: View {
    let level: Float

    var body: some View {
        Circle()
            .fill(Theme.statusDone)
            .frame(width: 5, height: 5)
            .opacity(0.25 + Double(min(level * 6, 0.75)))
    }
}
