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
                case .meeting:
                    if let meeting = app.selectedMeeting {
                        MeetingInspectorView(meeting: meeting)
                    }
                }
            }
            .padding(Theme.spaceL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgSidebar)
    }
}

/// One grouped block of the inspector: a card with a small title row and
/// hairline-separated content. The pane keeps the only ScrollView.
private struct InspectorCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusM, style: .continuous)
                .stroke(Theme.border, lineWidth: 1))
    }
}

private struct InspectorRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(Theme.textTertiary)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .font(.system(size: 12))
        .padding(.vertical, 7)
    }
}

private struct InspectorHairline: View {
    var body: some View {
        Rectangle().fill(Theme.border).frame(height: 1)
    }
}

/// The engine the idle Readiness card describes: the same configured default
/// `DictationController.start()` reads, with the same fallback for absent or
/// unknown values. The Apple-locale Language row is truthful only for the
/// local engine, so the idle pane guards on this exactly like the live
/// Session card guards on `dictation.engineID`.
enum DictationIdleEngine: Equatable {
    case local
    case muse

    init(configuredRaw: String?) {
        self = DictationEngineID(rawValue: configuredRaw ?? "local") == .muse ? .muse : .local
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
        VStack(alignment: .leading, spacing: Theme.spaceL) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Ready to dictate")
                    .font(Theme.sectionFont)
                    .foregroundStyle(Theme.textPrimary)
                Text("Hold \(DictationController.shortcutLabel) to dictate, or use Record on the Dictation page.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Ready to dictate")

            InspectorCard(title: "Readiness") {
                InspectorRow(label: "Engine", value: idleEngineLabel)
                if idleEngine == .local {
                    InspectorHairline()
                    InspectorRow(label: "Language", value: languageCode)
                }
                InspectorHairline()
                InspectorRow(label: "Auto-save", value: "Saves to history on device")
                if dictation.meetingIsRecording {
                    InspectorHairline()
                    HStack(spacing: 6) {
                        Circle().fill(Theme.statusLoading).frame(width: 6, height: 6)
                        Text("Mic in use — meeting recording")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .font(.system(size: 12))
                    .padding(.vertical, 7)
                }
            }
        }
    }

    private var liveContent: some View {
        VStack(alignment: .leading, spacing: Theme.spaceL) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(headline)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Text(engineLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.fillSubtle, in: Capsule())
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(headline), \(engineLabel)")

            if showsWaveform {
                InspectorWaveform(samples: dictation.waveform, active: dictation.phase == .listening)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        Theme.fillSubtle,
                        in: RoundedRectangle(cornerRadius: Theme.radiusS, style: .continuous))
            }

            if let elapsed = elapsedLabel {
                Text(elapsed)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .accessibilityLabel("Elapsed \(elapsed)")
            }

            HStack(alignment: .top, spacing: 3) {
                Text(bodyText)
                    .font(.system(size: 15))
                    .foregroundStyle(
                        dictation.preview.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if dictation.phase == .listening, !dictation.preview.isEmpty {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Theme.accent)
                        .frame(width: 2, height: 14)
                        .padding(.top, 3)
                        .accessibilityHidden(true)
                }
            }

            InspectorCard(title: "Session") {
                if dictation.engineID == .local {
                    InspectorRow(label: "Language", value: languageCode)
                    InspectorHairline()
                }
                // preferredLocale() is only the locale actually handed to the
                // Apple engine; Muse biases from a separate setting, so the
                // row would mislabel a Muse session. Hide it there.
                InspectorRow(label: "Auto-save", value: "Saves to history on device")
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

    private var idleEngine: DictationIdleEngine {
        DictationIdleEngine(configuredRaw: UserDefaults.standard.string(forKey: "dictationEngine"))
    }

    private var idleEngineLabel: String {
        idleEngine == .muse ? "Muse cloud" : "On device"
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

    private var headline: String {
        if dictation.phase == .listening, dictation.isToggle {
            return "Listening — press again to stop"
        }
        return statusTitle
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

private struct MeetingInspectorView: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting
    @State private var segments: [TranscriptSegment] = []
    @State private var confirmDelete = false

    private var folder: Folder? { app.folder(for: meeting) }
    private var calendarEvent: CalendarMeeting? {
        guard let id = meeting.calendarEventID else { return nil }
        return app.calendar.upcoming.first { $0.id == id }
    }
    private var talk: SpeakerTalkTime.Report {
        SpeakerTalkTime.report(segments: segments)
    }
    private var summaryText: String? {
        guard let summary = meeting.summary?
            .trimmingCharacters(in: .whitespacesAndNewlines), !summary.isEmpty
        else { return nil }
        return summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spaceL) {
            if let summaryText {
                InspectorCard(title: "Summary") {
                    Text(summaryText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.vertical, 2)
                }
            }

            InspectorCard(title: "Meeting details") {
                InspectorRow(
                    label: "Created",
                    value: meeting.createdAt.formatted(date: .abbreviated, time: .shortened))
                InspectorHairline()
                InspectorRow(
                    label: "Language",
                    value: meeting.language == "auto" ? "Auto" : meeting.language)
                if let folder {
                    InspectorHairline()
                    InspectorRow(
                        label: "Folder",
                        value: folder.team.map { "\($0) / \(folder.name)" } ?? folder.name)
                }
                if let duration = MeetingLibrary.durationLabel(
                    from: meeting.startedAt, to: meeting.endedAt)
                {
                    InspectorHairline()
                    InspectorRow(label: "Duration", value: duration)
                }
                if let event = calendarEvent {
                    InspectorHairline()
                    InspectorRow(label: "Calendar", value: event.title)
                    if let url = event.joinURL {
                        InspectorHairline()
                        InspectorRow(label: "Join", value: url.absoluteString)
                    }
                } else if let id = meeting.calendarEventID, !id.isEmpty {
                    InspectorHairline()
                    InspectorRow(label: "Calendar", value: id)
                }
                InspectorHairline()
                InspectorRow(label: "ID", value: meeting.id)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Meeting details")

            if !talk.rows.isEmpty {
                InspectorCard(title: "Speakers") {
                    HStack(spacing: 8) {
                        ForEach(talk.rows, id: \.speaker) { row in
                            HStack(spacing: 5) {
                                AvatarView(letterSource: row.speaker, size: 16)
                                Text(row.speaker)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                                Text(percent(row.share))
                                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(row.speaker) \(percent(row.share))")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 7)
                    stackedBar
                        .padding(.bottom, 4)
                    if talk.hasOverlap {
                        Text("Overlapping speech is counted for each speaker.")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            InspectorCard(title: "Quick actions") {
                actionRow("Export notes", systemImage: "square.and.arrow.up") {
                    if let db = app.database {
                        MeetingExporter.exportViaSavePanel(
                            meeting: meeting, database: db, folder: folder)
                    }
                }
                InspectorHairline()
                actionRow("Copy transcript", systemImage: "doc.on.doc") {
                    if let db = app.database {
                        MeetingExporter.copyTranscript(meeting: meeting, database: db)
                    }
                }
                if let draft = meeting.emailDraft, !draft.isEmpty {
                    InspectorHairline()
                    actionRow("Copy email", systemImage: "envelope") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(draft, forType: .string)
                        ToastController.shared.show("Email copied")
                    }
                }
                InspectorHairline()
                actionRow("Delete meeting", systemImage: "trash", destructive: true) {
                    confirmDelete = true
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: meeting.id) {
            guard let db = app.database else {
                segments = []
                return
            }
            let meetingID = meeting.id
            segments = await Task.detached(priority: .utility) {
                (try? db.fetchSegments(meetingID: meetingID, finalOnly: true)) ?? []
            }.value
        }
        .alert("Delete this meeting?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) { app.deleteMeeting(id: meeting.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The recording, transcript, and notes will be removed.")
        }
    }

    private func actionRow(
        _ title: String, systemImage: String, destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Label(title, systemImage: systemImage)
                    .font(.system(size: 12.5))
                    .foregroundStyle(
                        destructive ? Theme.statusListening.opacity(0.9) : Theme.textSecondary)
                    .labelStyle(.titleAndIcon)
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title == "Export notes" ? "Export as Markdown" : title)
    }

    private var stackedBar: some View {
        GeometryReader { geo in
            HStack(spacing: 1) {
                ForEach(talk.rows, id: \.speaker) { row in
                    Rectangle()
                        .fill(Theme.avatarColor(for: row.speaker))
                        .frame(width: max(2, geo.size.width * row.share))
                }
            }
        }
        .frame(height: 6)
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }

    private func percent(_ share: Double) -> String {
        "\(Int((share * 100).rounded()))%"
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
