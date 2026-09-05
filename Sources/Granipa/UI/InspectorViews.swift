import SwiftUI

struct InspectorPane: View {
    @Environment(AppState.self) private var app
    let kind: InspectorContentKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceL) {
                switch kind {
                case .none:
                    EmptyView()
                case .dictationIdle:
                    DictationInspectorView(dictation: app.dictation, isLive: false)
                case .dictationLive:
                    DictationInspectorView(dictation: app.dictation, isLive: true)
                }
            }
            .padding(Theme.spaceL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgSidebar)
    }
}

private struct DictationInspectorView: View {
    @Bindable var dictation: DictationController
    let isLive: Bool
    @State private var now = Date.now

    var body: some View {
        Group {
            if isLive {
                liveContent
                    .task { DictationSessionClock.shared.beginObserving() }
                    .task(id: dictation.phase) {
                        while dictation.phase == .preparing || dictation.phase == .listening {
                            now = .now
                            try? await Task.sleep(for: .milliseconds(500))
                        }
                    }
            } else {
                idleContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dictation off")
                .font(Theme.sectionFont)
                .foregroundStyle(Theme.textPrimary)
            Text("Hold \(DictationController.shortcutLabel) to dictate.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dictation off")
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: Theme.spaceL) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Text(engineLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.fillSubtle, in: Capsule())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(statusTitle), \(engineLabel)")

            if let elapsed = elapsedLabel {
                Text(elapsed)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityLabel("Elapsed \(elapsed)")
            }

            if showsWaveform {
                InspectorWaveform(samples: dictation.waveform, active: dictation.phase == .listening)
            }

            HStack(alignment: .top, spacing: 3) {
                Text(bodyText)
                    .font(.system(size: 15))
                    .foregroundStyle(
                        dictation.preview.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if dictation.phase == .listening, !dictation.preview.isEmpty {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.accent)
                        .frame(width: 2, height: 15)
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                }
            }

            HStack(spacing: 10) {
                // preferredLocale() is only the locale actually handed to the
                // Apple engine; Muse biases from a separate setting, so the
                // chip would mislabel a Muse session. Hide it there.
                if dictation.engineID == .local {
                    Text(languageCode)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.fillSubtle, in: Capsule())
                        .accessibilityLabel("Language \(languageCode)")
                }

                Label("Auto-saves to history", systemImage: "checkmark.shield")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
                    .labelStyle(.titleAndIcon)
            }

            if case .failed = dictation.phase, dictation.lastFailureRetryable {
                Button("Retry") { dictation.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live dictation")
    }

    private var showsWaveform: Bool {
        switch dictation.phase {
        case .preparing, .listening, .processing: true
        case .done, .failed, .idle: false
        }
    }

    private var elapsedLabel: String? {
        guard dictation.phase == .preparing || dictation.phase == .listening else { return nil }
        return DictationSessionClock.elapsedLabel(
            startedAt: DictationSessionClock.shared.sessionStartedAt, now: now)
    }

    private var languageCode: String {
        let locale = DictationController.preferredLocale()
        return locale.language.languageCode?.identifier.uppercased() ?? locale.identifier
    }

    private var statusTitle: String {
        switch dictation.phase {
        case .preparing: "Preparing"
        case .listening: "Listening"
        case .processing: dictation.isRewriting ? "Rewriting" : "Processing"
        case .done: "Pasted"
        case .failed: "Needs attention"
        case .idle: "Dictation off"
        }
    }

    private var bodyText: String {
        if case .failed(let message) = dictation.phase { return message }
        if !dictation.preview.isEmpty { return dictation.preview }
        switch dictation.phase {
        case .preparing: return "Getting the microphone ready…"
        case .listening: return dictation.isToggle ? "Speak — press again to finish" : "Speak now…"
        case .processing: return "Finishing your dictation…"
        case .done: return dictation.preview
        default: return statusTitle
        }
    }

    private var engineLabel: String {
        dictation.engineID == .muse ? "Muse" : "On device"
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

/// Static sample bars — the overlay's animated canvas stays the only
/// `TimelineView` render surface during a live session (contract §3.2b).
private struct InspectorWaveform: View {
    let samples: [Float]
    let active: Bool

    var body: some View {
        Canvas { context, size in
            let bars = DictationController.waveformBars
            let step = size.width / CGFloat(bars)
            let barWidth = step * 0.55
            let center = size.height / 2
            let values = samples.isEmpty ? [Float.zero] : samples
            for index in 0..<bars {
                let progress = CGFloat(index) / CGFloat(bars - 1)
                let position = progress * CGFloat(values.count - 1)
                let lower = min(Int(position), values.count - 1)
                let upper = min(lower + 1, values.count - 1)
                let fraction = position - CGFloat(lower)
                let value =
                    CGFloat(values[lower])
                    + (CGFloat(values[upper]) - CGFloat(values[lower])) * fraction
                let amplitude = max(1.5, abs(value) * size.height * 0.46)
                let rect = CGRect(
                    x: CGFloat(index) * step + (step - barWidth) / 2,
                    y: center - amplitude,
                    width: barWidth,
                    height: amplitude * 2)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(Theme.accent.opacity(active ? 0.92 : 0.38)))
            }
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}
