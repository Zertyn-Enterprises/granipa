import CoreGraphics
import Foundation
import Testing

@testable import Granipa

@Suite struct ShellNavigationTests {
    @Test func destinationChromeMatchesTheContract() {
        #expect(SidebarDestination.allCases.map(\.title) == [
            "Home", "Dictation", "Meetings", "Notes", "Files",
        ])
        #expect(SidebarDestination.home.icon == "house.fill")
        #expect(SidebarDestination.dictation.icon == "mic.fill")
        #expect(SidebarDestination.meetings.icon == "calendar")
        #expect(SidebarDestination.notes.icon == "note.text")
        #expect(SidebarDestination.files.icon == "folder")
    }

    @Test func openingAMeetingKeepsTheSourceDestinationHighlighted() {
        #expect(
            AppNavigation.highlight(destination: .home, selectedFolderID: nil)
                == .destination(.home))
        #expect(
            AppNavigation.highlight(destination: .meetings, selectedFolderID: nil)
                == .destination(.meetings))
        #expect(
            AppNavigation.isPrimaryActive(
                item: .home, destination: .home, selectedFolderID: nil))
        #expect(
            !AppNavigation.isPrimaryActive(
                item: .meetings, destination: .home, selectedFolderID: nil))
        #expect(
            AppNavigation.isPrimaryActive(
                item: .meetings, destination: .meetings, selectedFolderID: nil))
    }

    @Test func aSelectedFolderWinsOverPrimaryDestinations() {
        let highlight = AppNavigation.highlight(
            destination: .meetings, selectedFolderID: "eng")
        #expect(highlight == .folder("eng"))
        #expect(
            !AppNavigation.isPrimaryActive(
                item: .meetings, destination: .meetings, selectedFolderID: "eng"))
        #expect(
            !AppNavigation.isPrimaryActive(
                item: .home, destination: .home, selectedFolderID: "eng"))
    }

    @Test func notesListIsQuickNotesAndWrittenNotesOnly() {
        let quick = Meeting.new(title: "Quick", language: "auto")
        var recorded = Meeting.new(title: "Recorded", language: "auto")
        recorded.audioMicPath = "/tmp/mic.m4a"
        var noted = Meeting.new(title: "Noted", language: "auto")
        noted.audioMicPath = "/tmp/mic.m4a"
        noted.notesMarkdown = "  ship the shell  "
        var live = Meeting.new(title: "Live", language: "auto")
        live.status = .recording
        var whitespace = Meeting.new(title: "Whitespace", language: "auto")
        whitespace.notesMarkdown = "  \n"
        whitespace.audioSystemPath = "/tmp/sys.m4a"

        let notes = MeetingLibrary.notes(in: [quick, recorded, noted, live, whitespace])
        #expect(Set(notes.map(\.title)) == ["Quick", "Noted"])
    }

    @Test func filesListIsRecordingsAndLiveSessionsOnly() {
        let quick = Meeting.new(title: "Quick", language: "auto")
        var recorded = Meeting.new(title: "Recorded", language: "auto")
        recorded.audioSystemPath = "/tmp/sys.m4a"
        var live = Meeting.new(title: "Live", language: "auto")
        live.status = .recording

        let files = MeetingLibrary.recordings(in: [quick, recorded, live])
        #expect(Set(files.map(\.title)) == ["Recorded", "Live"])
    }

    @Test func folderCountsIgnoreUnfiledMeetings() {
        var a = Meeting.new(title: "A", language: "auto")
        a.folderID = "eng"
        var b = Meeting.new(title: "B", language: "auto")
        b.folderID = "eng"
        var c = Meeting.new(title: "C", language: "auto")
        c.folderID = "prod"
        let loose = Meeting.new(title: "Loose", language: "auto")
        #expect(MeetingLibrary.folderCounts(from: [a, b, c, loose]) == ["eng": 2, "prod": 1])
    }

    @Test func sidebarSearchFiltersTitleAndNotes() {
        var alpha = Meeting.new(title: "Standup", language: "auto")
        alpha.notesMarkdown = "ship notes"
        let beta = Meeting.new(title: "Retro", language: "auto")
        let hits = MeetingLibrary.matching([alpha, beta], query: "SHIP")
        #expect(hits.map(\.title) == ["Standup"])
        #expect(MeetingLibrary.matching([alpha, beta], query: "  ").map(\.title) == ["Standup", "Retro"])
    }

    @Test func selectedMeetingHasNoInspectorOccupant() {
        let destinations: [SidebarDestination] = [.home, .meetings, .notes, .files]
        let widths: [CGFloat] = [1120, 1279, 1280, 1440]
        for destination in destinations {
            for width in widths {
                #expect(
                    AppNavigation.inspectorKind(
                        destination: destination,
                        dictationShowsInspector: false,
                        windowWidth: width) == .none)
                #expect(
                    AppNavigation.inspectorKind(
                        destination: destination,
                        dictationShowsInspector: true,
                        windowWidth: width) == .none)
            }
        }
    }

    @Test func idleDictationInspectorIsAvailableAtEveryWidth() {
        for width: CGFloat in [1120, 1279, 1280, 1440] {
            #expect(
                AppNavigation.inspectorKind(
                    destination: .dictation,
                    dictationShowsInspector: false,
                    windowWidth: width) == .dictationIdle)
        }
    }

    @Test func liveDictationInspectorDocksOnlyWhenWide() {
        #expect(
            AppNavigation.inspectorKind(
                destination: .dictation,
                dictationShowsInspector: true,
                windowWidth: 1120) == .none)
        #expect(
            AppNavigation.inspectorKind(
                destination: .dictation,
                dictationShowsInspector: true,
                windowWidth: 1279) == .none)
        #expect(
            AppNavigation.inspectorKind(
                destination: .dictation,
                dictationShowsInspector: true,
                windowWidth: 1280) == .dictationLive)
        #expect(
            AppNavigation.inspectorKind(
                destination: .dictation,
                dictationShowsInspector: true,
                windowWidth: 1440) == .dictationLive)
    }

    @Test func dictationInspectorPhasesExcludeIdleAndDone() {
        #expect(AppNavigation.dictationShowsInspector(.preparing))
        #expect(AppNavigation.dictationShowsInspector(.listening))
        #expect(AppNavigation.dictationShowsInspector(.processing))
        #expect(AppNavigation.dictationShowsInspector(.failed("mic busy")))
        #expect(!AppNavigation.dictationShowsInspector(.idle))
        #expect(!AppNavigation.dictationShowsInspector(.done))
    }

    @Test func durationLabelIsHonestAboutMissingTimes() {
        let start = Date(timeIntervalSince1970: 0)
        #expect(MeetingLibrary.durationLabel(from: nil, to: start) == nil)
        #expect(MeetingLibrary.durationLabel(from: start, to: start.addingTimeInterval(75)) == "1:15")
        #expect(
            MeetingLibrary.durationLabel(from: start, to: start.addingTimeInterval(3661))
                == "1:01:01")
    }

    @Test func fileStatusReportsMissingAndPresentFiles() throws {
        #expect(MeetingLibrary.fileStatus(path: nil) == nil)
        let missingPath = "/tmp/granipa-no-such-file-\(UUID().uuidString).m4a"
        #expect(MeetingLibrary.fileStatus(path: missingPath) == .missing)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-t1a-\(UUID().uuidString).m4a")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(MeetingLibrary.fileStatus(path: url.path) == .present(byteCount: 3))
        let cached = MeetingLibrary.fileStatuses(for: [url.path, missingPath])
        #expect(cached[url.path] == .present(byteCount: 3))
        #expect(cached[missingPath] == .missing)
    }

    @Test func fileLabelUsesCachedStatusWithoutTreatingPendingAsMissing() {
        let path = "/tmp/mic.m4a"
        #expect(MeetingLibrary.fileLabel(path: path, channel: "Me", status: nil) == "Me · mic.m4a")
        #expect(
            MeetingLibrary.fileLabel(path: path, channel: "Me", status: .missing)
                == "Me · Audio file missing")
        let size = ByteCountFormatter.string(fromByteCount: 3, countStyle: .file)
        #expect(
            MeetingLibrary.fileLabel(path: path, channel: "Them", status: .present(byteCount: 3))
                == "Them · mic.m4a · \(size)")
    }
}
