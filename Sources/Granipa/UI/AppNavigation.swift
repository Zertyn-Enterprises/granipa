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

    /// App sidebar destinations. Meetings, Notes, and Files remain leftover
    /// transient routes for fixtures; they are not sidebar entries.
    static var appDestinations: [SidebarDestination] {
        [.home, .dictation]
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

/// Home list type filter. Transient; not a persisted contract.
enum HomeLibraryFilter: String, CaseIterable, Sendable, Hashable, Identifiable {
    case all
    case notes
    case recordings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .notes: "Notes"
        case .recordings: "Recordings"
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
    /// Leftover Meetings/Notes/Files routes highlight Home, never a removed row.
    static func resolvedAppDestination(_ destination: SidebarDestination) -> SidebarDestination {
        switch destination {
        case .meetings, .notes, .files: .home
        case .home, .dictation, .settings: destination
        }
    }

    static func highlight(
        destination: SidebarDestination,
        selectedFolderID: String?
    ) -> SidebarHighlight {
        if let selectedFolderID {
            return .folder(selectedFolderID)
        }
        return .destination(resolvedAppDestination(destination))
    }

    static func activeLibraryFilter(
        destination: SidebarDestination,
        stored: HomeLibraryFilter
    ) -> HomeLibraryFilter {
        switch destination {
        case .notes: .notes
        case .files: .recordings
        case .meetings: .all
        case .home, .dictation, .settings: stored
        }
    }

    static func showsHomeCalendarCard(
        filter: HomeLibraryFilter,
        isSearching: Bool,
        hasFolder: Bool
    ) -> Bool {
        filter == .all && !isSearching && !hasFolder
    }

    /// Sidebar and leftover library reveals. Filter is kept on Home/Dictation.
    static func reveal(
        _ destination: SidebarDestination,
        currentFilter: HomeLibraryFilter
    ) -> (destination: SidebarDestination, filter: HomeLibraryFilter) {
        switch destination {
        case .notes: (.home, .notes)
        case .files: (.home, .recordings)
        case .meetings: (.home, .all)
        case .home, .dictation, .settings: (destination, currentFilter)
        }
    }

    static func selectingFilter(
        _ filter: HomeLibraryFilter,
        destination: SidebarDestination
    ) -> (destination: SidebarDestination, filter: HomeLibraryFilter) {
        switch destination {
        case .meetings, .notes, .files: (.home, filter)
        case .home, .dictation, .settings: (destination, filter)
        }
    }

    /// Collections stay on Home so the header is never a Meetings page.
    static let folderRevealDestination: SidebarDestination = .home

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
        var libraryFilter: HomeLibraryFilter = .all

        static func snapshot(
            destination: SidebarDestination,
            selectedMeetingID: String?,
            selectedFolderID: String?,
            libraryFilter: HomeLibraryFilter = .all
        ) -> SettingsReturn? {
            guard destination != .settings else { return nil }
            return SettingsReturn(
                destination: destination,
                selectedMeetingID: selectedMeetingID,
                selectedFolderID: selectedFolderID,
                libraryFilter: libraryFilter)
        }
    }

    static func leaveSettings(_ snapshot: SettingsReturn?) -> SettingsReturn {
        snapshot
            ?? SettingsReturn(
                destination: .home, selectedMeetingID: nil, selectedFolderID: nil,
                libraryFilter: .all)
    }
}

enum MeetingLibrary {
    static func isSearching(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func libraryBase(
        meetings: [Meeting],
        searchResults: [Meeting],
        isSearching: Bool
    ) -> [Meeting] {
        isSearching ? searchResults : meetings
    }

    static func acceptSearch(
        finishedQuery: String,
        currentQuery: String,
        cancelled: Bool
    ) -> Bool {
        !cancelled && finishedQuery == currentQuery
    }

    static func shown(
        in meetings: [Meeting],
        filter: HomeLibraryFilter,
        folderID: String?
    ) -> [Meeting] {
        let typed: [Meeting]
        switch filter {
        case .all: typed = meetings
        case .notes: typed = notes(in: meetings)
        case .recordings: typed = recordings(in: meetings)
        }
        guard let folderID else { return typed }
        return typed.filter { $0.folderID == folderID }
    }

    static func recordingPaths(in meetings: [Meeting]) -> [String] {
        var seen = Set<String>()
        var paths: [String] = []
        for meeting in recordings(in: meetings) {
            for path in [meeting.audioMicPath, meeting.audioSystemPath].compactMap({ $0 }) {
                if seen.insert(path).inserted {
                    paths.append(path)
                }
            }
        }
        return paths
    }

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
