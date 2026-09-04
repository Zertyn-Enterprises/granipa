import SwiftUI

struct DictationOverlayView: View {
    @Environment(DictationController.self) private var dictation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isLive: Bool {
        dictation.phase == .listening || dictation.phase == .preparing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text(bodyText)
                .font(.system(size: 15.5, weight: .medium))
                .foregroundStyle(textColor)
                .lineSpacing(2)
                .lineLimit(2)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .topLeading)

            VoiceWaveform(
                samples: dictation.waveform,
                isActive: isLive,
                reduceMotion: reduceMotion)
            .frame(height: 30)
        }
        .padding(14)
        .frame(width: 440, height: 132, alignment: .topLeading)
        .background(
            Theme.card.opacity(0.98),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(
                    isLive ? Theme.brandPink.opacity(0.34) : Theme.strokeStrong,
                    lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
        .padding(16)
        .frame(maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .animation(
            reduceMotion ? nil : .easeOut(duration: Theme.motionNormal),
            value: dictation.phase)
    }

    private var header: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(dotColor.opacity(0.16))
                Image(systemName: statusIcon)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(dotColor)
            }
            .frame(width: 20, height: 20)

            Text(statusTitle.uppercased())
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
                .tracking(0.7)

            Text(engineLabel)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Theme.fillSubtle, in: Capsule())

            Spacer(minLength: 8)
            trailingAction
        }
    }

    @ViewBuilder
    private var trailingAction: some View {
        if isLive {
            Button {
                dictation.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 22, height: 22)
                    .background(Theme.fillSubtle, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")
        } else if case .failed = dictation.phase, dictation.lastFailureRetryable {
            Button("Retry") {
                dictation.retry()
            }
            .font(.system(size: 13, weight: .semibold))
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .controlSize(.regular)
        }
    }

    private var statusTitle: String {
        switch dictation.phase {
        case .preparing: "Preparing"
        case .listening: "Listening"
        case .processing: dictation.isRewriting ? "Rewriting" : "Processing"
        case .done: "Pasted"
        case .failed: "Needs attention"
        case .idle: ""
        }
    }

    private var statusIcon: String {
        switch dictation.phase {
        case .preparing: "ellipsis"
        case .listening: "waveform"
        case .processing: "sparkles"
        case .done: "checkmark"
        case .failed: "exclamationmark"
        case .idle: "mic.fill"
        }
    }

    private var engineLabel: String {
        dictation.engineID == .muse ? "Muse" : "On device"
    }

    private var bodyText: String {
        if case .failed(let message) = dictation.phase { return message }
        if !dictation.preview.isEmpty { return dictation.preview }
        switch dictation.phase {
        case .preparing: return "Getting the microphone ready…"
        case .listening: return dictation.isToggle ? "Speak — press again to finish" : "Speak now…"
        case .processing: return "Finishing your dictation…"
        case .done: return dictation.preview
        default: return ""
        }
    }

    private var textColor: Color {
        dictation.preview.isEmpty ? Theme.textSecondary : Theme.textPrimary
    }

    private var dotColor: Color {
        switch dictation.phase {
        case .preparing: Theme.statusLoading
        case .listening: Theme.statusListening
        case .processing: Theme.statusProcessing
        case .done: Theme.statusDone
        case .failed: Theme.statusFailed
        case .idle: Theme.textTertiary
        }
    }
}

private struct VoiceWaveform: View {
    let samples: [Float]
    let isActive: Bool
    let reduceMotion: Bool

    var body: some View {
        TimelineView(
            .animation(
                minimumInterval: reduceMotion ? nil : 1.0 / 30.0,
                paused: reduceMotion || !isActive)
        ) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate * 5.5
            Canvas(opaque: false, colorMode: .linear, rendersAsynchronously: true) {
                context, size in
                let path = waveformPath(in: size, phase: phase)
                let gradient = Gradient(colors: [
                    Theme.brandPurple.opacity(0.9),
                    Theme.brandPink,
                    Theme.accent.opacity(0.92),
                ])
                context.fill(
                    path,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: size.height / 2),
                        endPoint: CGPoint(x: size.width, y: size.height / 2)))
            }
        }
        .opacity(isActive ? 1 : 0.34)
    }

    private func waveformPath(in size: CGSize, phase: Double) -> Path {
        let values = samples.isEmpty ? [Float.zero] : samples
        let pointCount = 72
        let centerY = size.height / 2
        var upper: [CGPoint] = []
        var lower: [CGPoint] = []
        upper.reserveCapacity(pointCount)
        lower.reserveCapacity(pointCount)

        for point in 0..<pointCount {
            let progress = CGFloat(point) / CGFloat(pointCount - 1)
            let samplePosition = progress * CGFloat(values.count - 1)
            let lowerIndex = min(Int(samplePosition), values.count - 1)
            let upperIndex = min(lowerIndex + 1, values.count - 1)
            let fraction = samplePosition - CGFloat(lowerIndex)
            let sample = CGFloat(values[lowerIndex])
                + (CGFloat(values[upperIndex]) - CGFloat(values[lowerIndex])) * fraction
            let edgeEnvelope = pow(sin(.pi * progress), 0.42)
            let motion = 0.76 + 0.24 * sin(progress * .pi * 12 - phase)
            let amplitude = edgeEnvelope * motion * (1.5 + sample * (size.height * 0.46))
            let drift = sin(progress * .pi * 2 + phase * 0.18) * 0.7
            let x = progress * size.width
            upper.append(CGPoint(x: x, y: centerY + drift - amplitude))
            lower.append(CGPoint(x: x, y: centerY + drift + amplitude))
        }

        var path = Path()
        if let first = upper.first {
            path.move(to: first)
            for point in upper.dropFirst() { path.addLine(to: point) }
            for point in lower.reversed() { path.addLine(to: point) }
            path.closeSubpath()
        }
        return path
    }
}
