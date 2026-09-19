import SwiftUI

enum PlaybackTransport {
    static let ringSize: CGFloat = 44
    static let innerSize: CGFloat = 28

    static func progress(current: TimeInterval, duration: TimeInterval) -> CGFloat {
        guard duration > 0, duration.isFinite, current.isFinite else { return 0 }
        return CGFloat(min(1, max(0, current / duration)))
    }
}

struct MeetingPlaybackBar: View {
    @Environment(AppState.self) private var app
    @Bindable var playback: MeetingPlaybackController
    let meeting: Meeting

    @State private var peaks: [Float]?

    private var isRecordingThisMeeting: Bool {
        app.recorder.isRecording && app.recorder.meetingID == meeting.id
    }

    private var hasAudioPaths: Bool {
        meeting.audioMicPath != nil || meeting.audioSystemPath != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isRecordingThisMeeting {
                RecordingBar(meeting: meeting)
            } else if hasAudioPaths {
                playerRow
                if case .failed(let error) = playback.state {
                    AudioWarningLabel(text: errorLabel(error), icon: "speaker.slash")
                }
            } else {
                RecordingBar(meeting: meeting)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: Theme.radiusL)
        .task(id: playback.loadedURL?.path) {
            peaks = nil
            guard let url = playback.loadedURL else { return }
            let decoded = await Task.detached(priority: .utility) {
                MeetingWaveform.decode(url: url)
            }.value
            guard !Task.isCancelled else { return }
            peaks = decoded
        }
    }

    private var playerRow: some View {
        ViewThatFits(in: .horizontal) {
            controls(compact: false)
            controls(compact: true)
        }
    }

    private func controls(compact: Bool) -> some View {
        let transport = HStack(spacing: 10) {
            playButton
            Text(clock(playback.currentTime))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textSecondary)
                .frame(minWidth: 36, alignment: .leading)
                .accessibilityLabel("Elapsed \(clock(playback.currentTime))")

            PlaybackScrubber(
                peaks: peaks,
                progress: progress,
                enabled: playback.duration > 0 && canControl
            ) { fraction in
                playback.seek(to: fraction * playback.duration)
            }
            .frame(minWidth: compact ? 80 : 140)
            .layoutPriority(1)

            Text(clock(playback.duration))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(Theme.textTertiary)
                .frame(minWidth: 36, alignment: .trailing)
                .accessibilityLabel("Duration \(clock(playback.duration))")
        }

        let extras = HStack(spacing: 8) {
            rateMenu
            if playback.availableChannels.count > 1 {
                channelPicker
            }
            recordButton
        }

        return Group {
            if compact {
                VStack(alignment: .leading, spacing: 8) {
                    transport
                    extras
                }
            } else {
                HStack(spacing: 10) {
                    transport
                    extras
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var playButton: some View {
        if playback.state == .preparing {
            ZStack {
                Circle()
                    .stroke(Theme.fillSubtle, lineWidth: 3)
                ProgressView()
                    .controlSize(.small)
            }
            .frame(width: PlaybackTransport.ringSize, height: PlaybackTransport.ringSize)
            .accessibilityLabel("Preparing audio")
        } else {
            Button {
                playback.togglePlaying()
            } label: {
                ZStack {
                    Circle()
                        .stroke(Theme.fillSubtle, lineWidth: 3)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            Theme.accent,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .offset(x: playback.isPlaying ? 0 : 0.5)
                        .frame(
                            width: PlaybackTransport.innerSize,
                            height: PlaybackTransport.innerSize)
                        .background(Theme.accent, in: Circle())
                }
                .frame(width: PlaybackTransport.ringSize, height: PlaybackTransport.ringSize)
            }
            .buttonStyle(.plain)
            .disabled(!canControl)
            .accessibilityLabel(playback.isPlaying ? "Pause" : "Play")
            .help(playback.isPlaying ? "Pause" : "Play")
        }
    }

    private var rateMenu: some View {
        Menu {
            ForEach(MeetingPlaybackController.rates, id: \.self) { rate in
                Button(rateLabel(rate)) { playback.setRate(rate) }
            }
        } label: {
            Text(rateLabel(playback.rate))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Theme.fillSubtle, in: Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(!canControl)
        .accessibilityLabel("Playback speed")
        .help("Playback speed")
    }

    private var channelPicker: some View {
        Picker("Audio channel", selection: channelBinding) {
            if playback.availableChannels.contains(.mic) {
                Text("Mic").tag(AudioChannel.mic)
            }
            if playback.availableChannels.contains(.system) {
                Text("System").tag(AudioChannel.system)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.small)
        .frame(maxWidth: 150)
        .labelsHidden()
        .accessibilityLabel("Audio channel")
        .help("Play the microphone or system recording — not both")
    }

    private var recordButton: some View {
        Button {
            app.startRecording(meetingID: meeting.id)
        } label: {
            Label("Record", systemImage: "record.circle")
                .font(.system(size: 12, weight: .semibold))
                .labelStyle(.titleAndIcon)
        }
        .granipaPrimaryControl()
        .controlSize(.small)
        .disabled(app.recorder.isBusy)
        .help(app.recorder.isBusy ? "Recording" : "Record")
        .accessibilityLabel(app.recorder.isBusy ? "Recording" : "Record")
    }

    private var channelBinding: Binding<AudioChannel> {
        Binding(
            get: { playback.channel },
            set: { playback.selectChannel($0) })
    }

    private var canControl: Bool {
        switch playback.state {
        case .ready, .playing, .paused, .ended: true
        case .idle, .preparing, .failed: false
        }
    }

    private var progress: CGFloat {
        PlaybackTransport.progress(current: playback.currentTime, duration: playback.duration)
    }

    private func clock(_ seconds: TimeInterval) -> String {
        LiveStageFormat.elapsed(Int(seconds.rounded(.down)))
    }

    private func rateLabel(_ rate: Float) -> String {
        if rate == 1 { return "1x" }
        if rate == 1.5 { return "1.5x" }
        if rate == 2 { return "2x" }
        return String(format: "%.1fx", rate)
    }

    private func errorLabel(_ error: MeetingPlaybackError) -> String {
        switch error {
        case .missingFile: "Audio file missing"
        case .loadFailed(let message): message
        }
    }
}

struct PlaybackScrubber: View {
    let peaks: [Float]?
    let progress: CGFloat
    var enabled: Bool = true
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let peaks, !peaks.isEmpty {
                    waveform(peaks, size: geo.size)
                } else {
                    Capsule().fill(Theme.fillSubtle)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(4, geo.size.width * progress))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard enabled, geo.size.width > 0 else { return }
                        onSeek(min(1, max(0, value.location.x / geo.size.width)))
                    }
            )
            .accessibilityLabel("Seek")
            .accessibilityValue("\(Int((progress * 100).rounded())) percent")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                let step: CGFloat = 0.05
                switch direction {
                case .increment: onSeek(Double(min(1, progress + step)))
                case .decrement: onSeek(Double(max(0, progress - step)))
                @unknown default: break
                }
            }
        }
        .frame(height: 44)
        .opacity(enabled ? 1 : 0.45)
        .allowsHitTesting(enabled)
    }

    private func waveform(_ peaks: [Float], size: CGSize) -> some View {
        let count = peaks.count
        let step = size.width / CGFloat(max(count, 1))
        let barWidth = max(1, step * 0.55)
        let played = Int((progress * CGFloat(count)).rounded(.down))
        return Canvas { context, _ in
            let center = size.height / 2
            for (index, value) in peaks.enumerated() {
                let amplitude = max(1.6, CGFloat(value) * size.height * 0.46)
                let rect = CGRect(
                    x: CGFloat(index) * step + (step - barWidth) / 2,
                    y: center - amplitude,
                    width: barWidth,
                    height: amplitude * 2)
                let color = index <= played ? Theme.accent : Theme.textTertiary.opacity(0.55)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: barWidth / 2),
                    with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }
}
