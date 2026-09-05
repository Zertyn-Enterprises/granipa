import SwiftUI

/// Stage state for the selected recording meeting (contract §3.3).
enum LiveStageState: Equatable {
    case starting
    case recording
    /// Live transcription failed while capture continues; Stop still works.
    case transcriptionFailed(String)

    var isCapturing: Bool {
        if case .transcriptionFailed = self { return true }
        return self == .recording
    }
}

enum LiveStage {
    /// nil when the engine is neither starting nor recording — the stage
    /// must not show (contract §3.3: recording meeting selected, else nothing).
    static func state(
        isRecording: Bool,
        isStarting: Bool,
        transcriptionPhase: TranscriptionCoordinator.Phase?
    ) -> LiveStageState? {
        if isRecording {
            if case .failed(let message) = transcriptionPhase {
                return .transcriptionFailed(message)
            }
            return .recording
        }
        return isStarting ? .starting : nil
    }
}

enum LiveStageFormat {
    /// HH:MM:SS from one hour on, M:SS below it (contract §3.3).
    static func elapsed(_ seconds: Int) -> String {
        let total = max(0, seconds)
        if total >= 3600 {
            return String(format: "%02d:%02d:%02d", total / 3600, total % 3600 / 60, total % 60)
        }
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

enum LiveStageLayout {
    /// Width at which notes sit beside the live transcript under a full-width
    /// stage. The default window's content column (1120 − 248 = 872) clears
    /// this; anything narrower stacks transcript then notes so Quick note can
    /// still scroll the editor onscreen.
    static let twoColumnMinWidth: CGFloat = 864

    enum Arrangement: Equatable {
        case stacked
        case notesBesideTranscript
    }

    static func isTwoColumn(width: CGFloat) -> Bool {
        width >= twoColumnMinWidth
    }

    static func arrangement(width: CGFloat, hasTranscript: Bool) -> Arrangement {
        if isTwoColumn(width: width) && hasTranscript {
            return .notesBesideTranscript
        }
        return .stacked
    }
}

enum LiveNotesAnchor {
    /// Scroll target for Quick note. ⌘N while already focused must re-scroll.
    static let cardID = "live-notes-card"
}

/// Ring of the most recent gated RMS peaks, appended from observation of the
/// gated levels — no timer and no extra engine tap (contract §3.3 sparkline).
struct LevelHistory: Equatable {
    let capacity: Int
    private(set) var samples: [Float] = []

    init(capacity: Int = 64) {
        self.capacity = max(1, capacity)
    }

    mutating func append(_ level: Float) {
        samples.append(min(max(level, 0), 1))
        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }
    }
}

/// Full-page recording stage for the meeting being recorded. The floating
/// HUD stays independent and functional alongside it.
struct LiveRecordingView: View {
    @Environment(AppState.self) private var app
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let meeting: Meeting
    let quickNote: () -> Void
    @State private var levels = LevelHistory()

    private var state: LiveStageState? {
        LiveStage.state(
            isRecording: app.recorder.isRecording,
            isStarting: app.recorder.isStarting,
            transcriptionPhase: liveTranscription?.phase)
    }

    private var liveTranscription: TranscriptionCoordinator? {
        guard let coordinator = app.transcription, coordinator.meetingID == meeting.id else {
            return nil
        }
        return coordinator
    }

    private var languageCode: String {
        let language = app.meetings.first { $0.id == meeting.id }?.language ?? meeting.language
        return language == "auto" ? "Auto" : String(language.prefix(2)).uppercased()
    }

    private var languageRaw: String {
        app.meetings.first { $0.id == meeting.id }?.language ?? meeting.language
    }

    var body: some View {
        if let state {
            stageCard(state)
                .frame(maxWidth: .infinity)
        }
    }

    private func stageCard(_ state: LiveStageState) -> some View {
        VStack(spacing: Theme.spaceL) {
            ZStack {
                LiveStageRings()
                VStack(spacing: 10) {
                    timer(state)
                    statusLine(state)
                    Text(languageCode)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.fillSubtle, in: Capsule())
                        .accessibilityLabel("Language \(languageRaw)")
                }
            }
            .frame(minHeight: 188)
            .frame(maxWidth: .infinity)

            LiveLevelWaveform(samples: levels.samples)
                // Gated-RMS sparkline only (C5): gate-rate publish, and static
                // under Reduce Motion.
                .onChange(of: app.recorder.micLevel) { _, value in
                    guard !reduceMotion else { return }
                    levels.append(max(value, app.recorder.systemLevel))
                }
                .onChange(of: app.recorder.systemLevel) { _, value in
                    guard !reduceMotion else { return }
                    levels.append(max(app.recorder.micLevel, value))
                }

            HStack(spacing: Theme.spaceXL) {
                LevelMeter(label: "Mic", level: app.recorder.micLevel)
                    .accessibilityLabel("Microphone level")
                LevelMeter(label: "System", level: app.recorder.systemLevel)
                    .accessibilityLabel("System level")
            }

            transcriptionStatus
            warnings
            controls(state)
        }
        .padding(.horizontal, Theme.spaceXL)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(
            Theme.card,
            in: RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusL, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
    }

    @ViewBuilder
    private func statusLine(_ state: LiveStageState) -> some View {
        if state == .starting {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Starting…")
                    .font(Theme.fontBody.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            HStack(spacing: 8) {
                PulsingDot(color: Theme.statusListening)
                Text("Recording live…")
                    .font(Theme.fontBody.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }

    @ViewBuilder
    private func timer(_ state: LiveStageState) -> some View {
        if let started = app.recorder.startedAt, state.isCapturing {
            TimelineView(.periodic(from: started, by: 1)) { context in
                let text = LiveStageFormat.elapsed(Int(context.date.timeIntervalSince(started)))
                Text(text)
                    .font(.system(size: 76, weight: .light).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                    .accessibilityLabel("Recording time \(text)")
            }
        } else {
            Text(LiveStageFormat.elapsed(0))
                .font(.system(size: 76, weight: .light).monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
                .accessibilityLabel("Recording not started yet")
        }
    }

    @ViewBuilder
    private var transcriptionStatus: some View {
        if let live = liveTranscription {
            switch live.phase {
            case .preparing:
                Label(
                    "Preparing the speech model — the first recording on this Mac downloads it, "
                    + "which can take a few minutes.",
                    systemImage: "arrow.down.circle")
                    .font(Theme.fontCaption)
                    .foregroundStyle(Theme.textSecondary)
            case .failed(let message):
                TranscriptionFailedLabel(message: message) {
                    live.retryIfFailed()
                }
            default:
                EmptyView()
            }
        } else {
            Label("Transcript after you stop", systemImage: "text.quote")
                .font(Theme.fontCaption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    @ViewBuilder
    private var warnings: some View {
        if let warning = app.recorder.micWarning {
            AudioWarningLabel(text: warning, icon: "mic.slash")
        }
        if let warning = app.recorder.systemAudioWarning {
            AudioWarningLabel(text: warning)
        }
        if let warning = liveTranscription?.systemWarning {
            AudioWarningLabel(text: warning)
        }
    }

    private func controls(_ state: LiveStageState) -> some View {
        HStack(spacing: Theme.spaceL) {
            Button(action: quickNote) {
                Label("Quick note", systemImage: "square.and.pencil")
            }
            .buttonStyle(.bordered)
            .tint(.white)
            .keyboardShortcut("n", modifiers: .command)
            .help("Focus meeting notes (⌘N)")

            // Both states call stopRecording: it cancels a pending start and
            // discards its partial audio (AppState.stopRecording wasStarting).
            if state.isCapturing {
                Button {
                    Task { await app.stopRecording() }
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Theme.statusListening.opacity(0.45), lineWidth: 3)
                        Circle()
                            .fill(Theme.statusListening.opacity(0.16))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(Theme.statusListening)
                            .frame(width: 16, height: 16)
                    }
                    .frame(width: 56, height: 56)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(".", modifiers: .command)
                .help("Stop recording (⌘.)")
                .accessibilityLabel("Stop recording")
            } else {
                Button {
                    Task { await app.stopRecording() }
                } label: {
                    Label("Cancel", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .tint(Theme.statusFailed)
                .keyboardShortcut(".", modifiers: .command)
                .help("Cancel the recording start")
                .accessibilityLabel("Cancel starting the recording")
            }
        }
    }
}

struct LiveTranscriptPanel: View {
    let live: TranscriptionCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Theme.statusProcessing).frame(width: 7, height: 7)
                Text("Live transcript")
                    .font(Theme.fontCaption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }
            .padding(.horizontal, Theme.spaceL)
            .padding(.top, Theme.spaceL)
            .padding(.bottom, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        // Volatiles stay in the HUD and captions overlay; this
                        // list only carries finalized segments (contract §3.3).
                        ForEach(live.liveSegments) { segment in
                            SegmentRow(segment: segment)
                                .id(segment.id)
                        }
                        if live.liveSegments.isEmpty {
                            Text("Lines appear as speech is recognized.")
                                .font(Theme.fontCaption)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.horizontal, Theme.spaceL)
                    .padding(.bottom, Theme.spaceL)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 160, maxHeight: 280)
                .onChange(of: live.liveSegments.count) { _, _ in
                    if let last = live.liveSegments.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: Theme.radiusL)
    }
}

private struct PulsingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let color: Color
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// Decorative bars from the gated level history — not an audio-accurate
/// trace; the meters carry the real levels.
private struct LiveLevelWaveform: View {
    static let barCount = 64
    let samples: [Float]

    var body: some View {
        Canvas { context, size in
            let values = samples.isEmpty ? [Float.zero] : samples
            let step = size.width / CGFloat(Self.barCount)
            let barWidth = step * 0.5
            let center = size.height / 2
            for index in 0..<Self.barCount {
                let progress = CGFloat(index) / CGFloat(Self.barCount - 1)
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
                    with: .color(Theme.statusListening.opacity(0.85)))
            }
        }
        .frame(height: 56)
        .accessibilityHidden(true)
    }
}

/// Static concentric rings behind the timer. Not animated — Reduce Motion
/// does not need a branch (contract: no looping ambient animation).
private struct LiveStageRings: View {
    private static let diameters: [CGFloat] = [176, 248, 320]

    var body: some View {
        ZStack {
            ForEach(Array(Self.diameters.enumerated()), id: \.offset) { index, diameter in
                Circle()
                    .stroke(
                        Theme.statusListening.opacity(0.20 - Double(index) * 0.05),
                        lineWidth: 1)
                    .frame(width: diameter, height: diameter)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
