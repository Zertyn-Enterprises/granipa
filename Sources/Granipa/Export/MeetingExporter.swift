import AppKit
import Foundation
import UniformTypeIdentifiers

enum MeetingExporter {
    static func markdown(meeting: Meeting, segments: [TranscriptSegment], folder: Folder?) -> String {
        var parts: [String] = []
        parts.append("# \(meeting.title)")

        var meta = meeting.createdAt.formatted(date: .long, time: .shortened)
        if let folder {
            meta += " · \(folder.team.map { "\($0) / " } ?? "")\(folder.name)"
        }
        parts.append(meta)

        if let summary = meeting.summary, !summary.isEmpty {
            parts.append("## Summary\n\n\(summary)")
        }
        if let notes = meeting.enhancedNotesMarkdown, !notes.isEmpty {
            parts.append("## Notes\n\n\(notes)")
        } else if !meeting.notesMarkdown.isEmpty {
            parts.append("## Notes\n\n\(meeting.notesMarkdown)")
        }

        let items = ActionItem.decodeList(from: meeting.actionItemsJSON)
        if !items.isEmpty {
            let list = items
                .map { "- [ ] \($0.text)\($0.owner.map { " — \($0)" } ?? "")" }
                .joined(separator: "\n")
            parts.append("## Action items\n\n\(list)")
        }
        if let draft = meeting.emailDraft, !draft.isEmpty {
            parts.append("## Follow-up email draft\n\n\(draft)")
        }
        if !segments.isEmpty {
            parts.append(
                "## Transcript\n\n\(EnhancementService.transcriptText(segments: segments))")
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    static func suggestedFileName(for meeting: Meeting) -> String {
        let safe = meeting.title
            .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        return (safe.isEmpty ? "Meeting" : safe) + ".md"
    }

    @MainActor
    static func exportViaSavePanel(meeting: Meeting, database: AppDatabase, folder: Folder?) {
        let segments = (try? database.fetchSegments(meetingID: meeting.id, finalOnly: true)) ?? []
        let content = markdown(meeting: meeting, segments: segments, folder: folder)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedFileName(for: meeting)
        if let markdownType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [markdownType]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? content.write(to: url, atomically: true, encoding: .utf8)
        ToastController.shared.show("Exported")
    }

    @MainActor
    static func copyTranscript(meeting: Meeting, database: AppDatabase) {
        let segments = (try? database.fetchSegments(meetingID: meeting.id, finalOnly: true)) ?? []
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(
            EnhancementService.transcriptText(segments: segments), forType: .string)
        ToastController.shared.show("Transcript copied")
    }
}
