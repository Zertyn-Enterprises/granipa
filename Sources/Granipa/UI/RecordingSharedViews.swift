import SwiftUI

extension MeetingPipelinePhase {
    var isLive: Bool {
        switch self {
        case .recording, .finishing, .transcribing, .enhancing, .failed: true
        case .idle, .ready: false
        }
    }

    var label: String {
        switch self {
        case .idle, .ready: ""
        case .recording: "Recording"
        case .finishing: "Finishing"
        case .transcribing: "Transcribing"
        case .enhancing: "Enhancing"
        case .failed: "Failed"
        }
    }

    var systemImage: String {
        switch self {
        case .idle, .ready: ""
        case .recording: "record.circle"
        case .finishing: "arrow.down.circle"
        case .transcribing: "text.quote"
        case .enhancing: "wand.and.stars"
        case .failed: "xmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .idle, .ready: Theme.textSecondary
        case .recording: Theme.statusListening
        case .finishing: Theme.statusLoading
        case .transcribing, .enhancing: Theme.statusProcessing
        case .failed: Theme.statusFailed
        }
    }
}

struct RecordingTimer: View {
    let startedAt: Date

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            Text(Self.elapsed(from: startedAt, to: context.date))
                .monospacedDigit()
        }
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}

struct AudioWarningLabel: View {
    let text: String
    var icon = "exclamationmark.triangle.fill"

    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(Theme.statusFailed)
    }
}

struct TranscriptionFailedLabel: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Label("Transcription failed: \(message)", systemImage: "xmark.circle")
                .font(.caption)
                .foregroundStyle(Theme.statusFailed)
                .lineLimit(2)
            Button("Retry", action: retry)
                .controlSize(.small)
        }
    }
}

struct LiveTranscriptSnippet: View {
    enum Style {
        case hud
        case captions
    }

    let lastSegment: TranscriptSegment?
    let volatileSystem: String
    let volatileMic: String
    let style: Style

    var body: some View {
        switch style {
        case .hud: hudBody
        case .captions: captionsBody
        }
    }

    private var hudBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let lastSegment {
                Text("\(lastSegment.speaker): \(lastSegment.text)")
                    .font(.system(size: 22, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.head)
                    .foregroundStyle(Theme.textSecondary)
            }
            if !volatileSystem.isEmpty {
                Text("Them: \(volatileSystem)")
                    .font(.system(size: 22, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.head)
                    .italic()
                    .foregroundStyle(Theme.textTertiary)
            } else if !volatileMic.isEmpty {
                Text("Me: \(volatileMic)")
                    .font(.system(size: 22, weight: .medium))
                    .lineLimit(2)
                    .truncationMode(.head)
                    .italic()
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captionsBody: some View {
        Group {
            if let lastSegment {
                captionLine(speaker: lastSegment.speaker, text: lastSegment.text, volatile: false)
            }
            if !volatileSystem.isEmpty {
                captionLine(speaker: "Them", text: volatileSystem, volatile: true)
            } else if !volatileMic.isEmpty {
                captionLine(speaker: "Me", text: volatileMic, volatile: true)
            }
        }
    }

    var isEmpty: Bool {
        lastSegment == nil && volatileSystem.isEmpty && volatileMic.isEmpty
    }

    private func captionLine(speaker: String, text: String, volatile: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(speaker)
                .font(Theme.fontCaption.weight(.semibold))
                .foregroundStyle(speaker == "Me" ? Theme.channelMe : Theme.accent)
            Text(text)
                .font(.system(size: 17, weight: .medium))
                .italic(volatile)
                .foregroundStyle(volatile ? Theme.textSecondary : Theme.textPrimary)
                .lineLimit(2)
                .truncationMode(.head)
        }
    }
}
