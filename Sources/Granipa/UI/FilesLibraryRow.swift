import SwiftUI

struct FilesLibraryRow: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting
    let fileStatuses: [String: RecordingFileStatus]

    private var isLive: Bool { meeting.status == .recording }
    private var folder: Folder? { app.folder(for: meeting) }
    private var phase: MeetingPipelinePhase { app.pipelinePhase(for: meeting) }

    private var fileLines: [String] {
        var lines: [String] = []
        if let path = meeting.audioMicPath {
            lines.append(
                MeetingLibrary.fileLabel(
                    path: path, channel: "Me", status: fileStatuses[path]))
        }
        if let path = meeting.audioSystemPath {
            lines.append(
                MeetingLibrary.fileLabel(
                    path: path, channel: "Them", status: fileStatuses[path]))
        }
        return lines
    }

    var body: some View {
        Button {
            app.selectedMeetingID = meeting.id
        } label: {
            HStack(alignment: .top, spacing: 14) {
                AvatarView(letterSource: meeting.title, fallbackIcon: "waveform", size: 42)
                VStack(alignment: .leading, spacing: 6) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    if isLive {
                        Text("Recording…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.statusListening)
                    } else if !fileLines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(fileLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                            }
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                    }
                    LibraryMetaRow(
                        status: isLive ? nil : (phase.isLive ? phase.label : nil),
                        folder: folder?.name,
                        duration: MeetingLibrary.durationLabel(
                            from: meeting.startedAt, to: meeting.endedAt),
                        date: meeting.createdAt)
                }
                Spacer(minLength: 8)
                Text(meeting.createdAt, format: .dateTime.hour().minute())
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .monospacedDigit()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressFadeButtonStyle())
        .card(cornerRadius: Theme.radiusM)
        .hoverHighlight(cornerRadius: Theme.radiusM)
        .contextMenu {
            MeetingRowContextMenu(meeting: meeting)
        }
        .accessibilityLabel(isLive ? "\(meeting.title), Recording" : meeting.title)
    }
}
