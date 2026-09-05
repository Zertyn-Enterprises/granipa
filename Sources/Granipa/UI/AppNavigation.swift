import CoreGraphics
import Foundation

enum SidebarDestination: String, CaseIterable, Sendable, Hashable {
    case home
    case dictation
    case meetings
    case notes
    case files
    /// Transient in-app Settings. Not persisted. Not a library destination.
    case settings

    /// The five library destinations shown in the app sidebar.
    static var appDestinations: [SidebarDestination] {
        allCases.filter { $0 != .settings }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .dictation: "Dictation"
        case .meetings: "Meetings"
        case .notes: "Notes"
        case .files: "Files"
        case .settings: "Settings"
        }
    }

    var icon: String {
        switch self {
        case .home: "house.fill"
        case .dictation: "mic.fill"
        case .meetings: "calendar"
        case .notes: "square.and.pencil"
        case .files: "folder.fill"
        case .settings: "gearshape"
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
    case meeting

    var hasContent: Bool { self != .none }

    /// Wide windows open live Dictation and the meeting inspector by default.
    /// Idle Dictation stays closed until the toolbar toggle is used.
    var expandsByDefault: Bool {
        switch self {
        case .meeting, .dictationLive: true
        case .none, .dictationIdle: false
        }
    }
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

    /// Library destinations keep a toolbar occupant so Home and Dictation
    /// share titlebar geometry. Settings uses a different chrome.
    static func showsInspectorToggle(destination: SidebarDestination) -> Bool {
        destination != .settings
    }

    static func inspectorToggleEnabled(kind: InspectorContentKind) -> Bool {
        kind.hasContent
    }

    static func inspectorKind(
        destination: SidebarDestination,
        dictationShowsInspector: Bool,
        windowWidth _: CGFloat,
        meetingSelected: Bool = false
    ) -> InspectorContentKind {
        if destination == .settings { return .none }
        if destination == .dictation {
            return dictationShowsInspector ? .dictationLive : .dictationIdle
        }
        return meetingSelected ? .meeting : .none
    }

    static func showsAppSidebar(for destination: SidebarDestination) -> Bool {
        destination != .settings
    }

    struct SettingsReturn: Equatable, Sendable {
        var destination: SidebarDestination
        var selectedMeetingID: String?
        var selectedFolderID: String?

        static func snapshot(
            destination: SidebarDestination,
            selectedMeetingID: String?,
            selectedFolderID: String?
        ) -> SettingsReturn? {
            guard destination != .settings else { return nil }
            return SettingsReturn(
                destination: destination,
                selectedMeetingID: selectedMeetingID,
                selectedFolderID: selectedFolderID)
        }
    }

    static func leaveSettings(_ snapshot: SettingsReturn?) -> SettingsReturn {
        snapshot
            ?? SettingsReturn(destination: .home, selectedMeetingID: nil, selectedFolderID: nil)
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
