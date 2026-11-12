import SwiftUI

struct NotesLibraryRow: View {
    @Environment(AppState.self) private var app
    let meeting: Meeting

    private var folder: Folder? { app.folder(for: meeting) }
    private var phase: MeetingPipelinePhase { app.pipelinePhase(for: meeting) }
    private var excerpt: String {
        LibraryCopy.excerpt(
            summary: meeting.summary,
            enhancedNotesMarkdown: meeting.enhancedNotesMarkdown,
            notesMarkdown: meeting.notesMarkdown)
            ?? MeetingLibrary.notePreview(meeting)
    }

    var body: some View {
        Button {
            app.selectedMeetingID = meeting.id
        } label: {
            HStack(alignment: .top, spacing: 14) {
                AvatarView(letterSource: meeting.title, fallbackIcon: "square.and.pencil", size: 42)
                VStack(alignment: .leading, spacing: 6) {
                    Text(meeting.title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(excerpt)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                    LibraryMetaRow(
                        status: phase.isLive ? phase.label : nil,
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
        .accessibilityLabel("\(meeting.title), \(excerpt)")
    }
}
