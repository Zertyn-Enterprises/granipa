import CoreGraphics
import Foundation

enum SidebarDestination: String, CaseIterable, Sendable, Hashable {
    case home
    case dictation
    case meetings
    case notes
    case files

    var title: String {
        switch self {
        case .home: "Home"
        case .dictation: "Dictation"
        case .meetings: "Meetings"
        case .notes: "Notes"
        case .files: "Files"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .dictation: "mic.fill"
        case .meetings: "calendar"
        case .notes: "note.text"
        case .files: "folder"
        }
    }
}

enum SidebarHighlight: Equatable, Sendable {
    case destination(SidebarDestination)
    case folder(String)
}

enum InspectorContentKind: Equatable, Sendable {
    case none
    case dictationIdle
    case dictationLive
}

enum RecordingFileStatus: Equatable, Sendable {
    case missing
    case present(byteCount: Int64)
}

enum AppNavigation {
    static func highlight(
        destination: SidebarDestination,
        selectedFolderID: String?
    ) -> SidebarHighlight {
        if let selectedFolderID {
            return .folder(selectedFolderID)
        }
        return .destination(destination)
    }

    static func isPrimaryActive(
        item: SidebarDestination,
        destination: SidebarDestination,
        selectedFolderID: String?
    ) -> Bool {
        highlight(destination: destination, selectedFolderID: selectedFolderID)
            == .destination(item)
    }

    static func dictationShowsInspector(_ phase: DictationPhase) -> Bool {
        switch phase {
        case .preparing, .listening, .processing, .failed: true
        case .idle, .done: false
        }
    }

    static func inspectorKind(
        destination: SidebarDestination,
        dictationShowsInspector: Bool,
        windowWidth: CGFloat
    ) -> InspectorContentKind {
        guard destination == .dictation else { return .none }
        if dictationShowsInspector {
            return windowWidth >= ShellLayout.inspectorBreakWidth ? .dictationLive : .none
        }
        return .dictationIdle
    }
}

enum MeetingLibrary {
    static func notes(in meetings: [Meeting]) -> [Meeting] {
        meetings.filter { meeting in
            let trimmed = meeting.notesMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return true }
            let hasAudio = meeting.audioMicPath != nil || meeting.audioSystemPath != nil
            return !hasAudio && meeting.status != .recording
        }
    }

    static func recordings(in meetings: [Meeting]) -> [Meeting] {
        meetings.filter { meeting in
            meeting.status == .recording
                || meeting.audioMicPath != nil
                || meeting.audioSystemPath != nil
        }
    }

    static func folderCounts(from meetings: [Meeting]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for meeting in meetings {
            if let folderID = meeting.folderID {
                counts[folderID, default: 0] += 1
            }
        }
        return counts
    }

    static func searchNotes(query: String, database: AppDatabase) -> [Meeting] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return notes(in: (try? database.searchMeetings(query: needle)) ?? [])
    }

    static func searchRecordings(query: String, database: AppDatabase) -> [Meeting] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        return recordings(in: (try? database.searchMeetings(query: needle)) ?? [])
    }

    static func dayGroups(from meetings: [Meeting]) -> [(day: Date, meetings: [Meeting])] {
        let grouped = Dictionary(grouping: meetings) {
            Calendar.current.startOfDay(for: $0.createdAt)
        }
        return grouped
            .sorted { $0.key > $1.key }
            .map { (day: $0.key, meetings: $0.value.sorted { $0.createdAt > $1.createdAt }) }
    }

    static func durationLabel(from start: Date?, to end: Date?) -> String? {
        guard let start, let end else { return nil }
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds >= 3600 {
            return String(
                format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
        }
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    /// Disk lookup. Call off the main actor and cache by path; do not use from a SwiftUI body.
    static func fileStatus(path: String?) -> RecordingFileStatus? {
        guard let path else { return nil }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            return .missing
        }
        let byteCount =
            (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
            .int64Value ?? 0
        return .present(byteCount: byteCount)
    }

    static func fileStatuses(for paths: [String]) -> [String: RecordingFileStatus] {
        var result: [String: RecordingFileStatus] = [:]
        result.reserveCapacity(paths.count)
        for path in paths {
            if let status = fileStatus(path: path) {
                result[path] = status
            }
        }
        return result
    }

    static func fileLabel(path: String, channel: String, status: RecordingFileStatus?) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        switch status {
        case nil:
            return "\(channel) · \(name)"
        case .missing:
            return "\(channel) · Audio file missing"
        case .present(let byteCount):
            let size = ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
            return "\(channel) · \(name) · \(size)"
        }
    }

    static func notePreview(_ meeting: Meeting) -> String {
        let lines = meeting.notesMarkdown
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if lines.isEmpty { return "Empty note" }
        return lines.prefix(2).joined(separator: "\n")
    }
}
