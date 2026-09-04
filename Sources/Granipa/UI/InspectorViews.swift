import SwiftUI

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.sectionFont)
                .foregroundStyle(Theme.textPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct InspectorPane: View {
    @Environment(AppState.self) private var app
    let kind: InspectorContentKind

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.spaceL) {
                switch kind {
                case .none:
                    EmptyView()
                case .meeting:
                    if let meeting = app.selectedMeeting {
                        MeetingInspectorView(meeting: meeting)
                    }
                case .dictationLive:
                    DictationInspectorView(dictation: app.dictation)
                }
            }
            .padding(Theme.spaceL)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bgSidebar)
    }
}

private struct MeetingInspectorView: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting
    @State private var speakers: [String] = []

    private var joinURL: URL? {
        guard let eventID = meeting.calendarEventID else { return nil }
        return app.calendar.upcoming.first { $0.id == eventID }?.joinURL
    }

    private var languageLabel: String {
        meeting.language == "auto" ? "Auto" : meeting.language
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spaceL) {
            InspectorSection(title: "Meeting details") {
                inspectorRow(
                    "Created",
                    meeting.createdAt.formatted(
                        .dateTime.weekday(.wide).month().day().hour().minute()))
                inspectorRow("Language", languageLabel)
                if let folder = app.folder(for: meeting) {
                    inspectorRow("Folder", folder.name)
                }
                durationBlock
                if let calendarID = meeting.calendarEventID, !calendarID.isEmpty {
                    inspectorRow("Calendar", calendarID)
                }
                if let joinURL {
                    Link(joinURL.absoluteString, destination: joinURL)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(2)
                }
                inspectorRow("ID", meeting.id)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Meeting details")

            if !speakers.isEmpty {
                InspectorSection(title: "Participants") {
                    ForEach(speakers, id: \.self) { name in
                        HStack(spacing: 8) {
                            AvatarView(letterSource: name, size: 22)
                            Text(name)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(1)
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Participants")
            }
        }
        .task(id: meeting.id) { await loadSpeakers() }
    }

    @ViewBuilder private var durationBlock: some View {
        if meeting.status == .recording, let startedAt = meeting.startedAt {
            HStack(alignment: .firstTextBaseline) {
                Text("Duration")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                RecordingTimer(startedAt: startedAt)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
            }
        } else if let duration = MeetingLibrary.durationLabel(
            from: meeting.startedAt, to: meeting.endedAt)
        {
            inspectorRow("Duration", duration)
        }
    }

    private func inspectorRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textPrimary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadSpeakers() async {
        guard let db = app.database else { return }
        let meetingID = meeting.id
        let loaded = await Task.detached(priority: .userInitiated) {
            (try? db.fetchSegments(meetingID: meetingID)) ?? []
        }.value
        guard !Task.isCancelled else { return }
        var seen = Set<String>()
        speakers = loaded.compactMap { segment in
            seen.insert(segment.speaker).inserted ? segment.speaker : nil
        }
    }
}

private struct DictationInspectorView: View {
    @Bindable var dictation: DictationController

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spaceL) {
            HStack(spacing: 8) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(engineLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.fillSubtle, in: Capsule())
            }

            InspectorWaveform(samples: dictation.waveform)
                .frame(height: 48)

            Text(bodyText)
                .font(.system(size: 15))
                .foregroundStyle(
                    dictation.preview.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if case .failed = dictation.phase, dictation.lastFailureRetryable {
                Button("Retry") { dictation.retry() }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
            }

            Label("Entries persist locally", systemImage: "checkmark.shield")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live dictation")
    }

    private var engineLabel: String {
        dictation.engineID == .muse ? "Muse" : "On device"
    }

    private var statusTitle: String {
        switch dictation.phase {
        case .preparing: "Getting the microphone ready…"
        case .listening:
            dictation.isToggle ? "Speak — press again to finish" : "Speak now…"
        case .processing: dictation.isRewriting ? "Rewriting" : "Finishing your dictation…"
        case .done: "Pasted"
        case .failed: "Needs attention"
        case .idle: "Dictation"
        }
    }

    private var bodyText: String {
        if case .failed(let message) = dictation.phase { return message }
        if !dictation.preview.isEmpty { return dictation.preview }
        return statusTitle
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

private struct InspectorWaveform: View {
    let samples: [Float]

    var body: some View {
        Canvas { context, size in
            let count = max(samples.count, 1)
            let slot = size.width / CGFloat(count)
            for (index, sample) in samples.enumerated() {
                let height = max(1, CGFloat(sample) * size.height)
                let rect = CGRect(
                    x: CGFloat(index) * slot + 1,
                    y: (size.height - height) / 2,
                    width: max(1, slot - 2),
                    height: height)
                context.fill(Path(rect), with: .color(Theme.accent.opacity(0.9)))
            }
        }
        .accessibilityHidden(true)
    }
}
