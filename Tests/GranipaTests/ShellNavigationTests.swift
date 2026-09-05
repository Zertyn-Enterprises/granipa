import CoreGraphics
import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct ShellNavigationTests {
    /// Human-approved Home unification (2026-09-05): header is Home, Search,
    /// or the selected folder name. The old `.library` "Meetings" title is gone.
    @Test func homeTitleStaysHomeUnlessSearchingOrInAFolder() {
        #expect(LibraryCopy.homeTitle(isSearching: false, folderName: nil) == "Home")
        #expect(LibraryCopy.homeTitle(isSearching: true, folderName: nil) == "Search")
        #expect(
            LibraryCopy.homeTitle(isSearching: false, folderName: "Engineering")
                == "Engineering")
    }

    /// NEW: human-approved Home unification. Sidebar app destinations are
    /// Home + Dictation only; Meetings/Notes/Files gather into Home filters.
    /// Observed red against feat/granipa-v2 before the unification change:
    /// appDestinations was ["Home", "Dictation", "Meetings", "Notes", "Files"].
    @Test func appSidebarDestinationsAreHomeAndDictationOnly() {
        #expect(SidebarDestination.appDestinations.map(\.title) == ["Home", "Dictation"])
        #expect(SidebarDestination.appDestinations == [.home, .dictation])
        #expect(!SidebarDestination.appDestinations.contains(.meetings))
        #expect(!SidebarDestination.appDestinations.contains(.notes))
        #expect(!SidebarDestination.appDestinations.contains(.files))
        #expect(!SidebarDestination.appDestinations.contains(.settings))
    }

    /// NEW: Home header is never a duplicate Meetings page.
    /// Observed red against feat/granipa-v2 (`mode: .library` returned "Meetings").
    @Test func homeHeaderIsNeverAMeetingsPage() {
        #expect(LibraryCopy.homeTitle(isSearching: false, folderName: nil) == "Home")
        #expect(LibraryCopy.homeTitle(isSearching: false, folderName: nil) != "Meetings")
        #expect(
            LibraryCopy.homeTitle(isSearching: true, folderName: "Engineering") == "Search")
        #expect(
            LibraryCopy.homeTitle(isSearching: false, folderName: "Engineering")
                != "Meetings")
    }

    @Test func libraryExcerptPrefersSummaryThenPlainNotesWithoutMarkdownMarkup() {
        #expect(
            LibraryCopy.excerpt(
                summary: "  Launch is imminent.  ",
                enhancedNotesMarkdown: "## Decisions\n- ignored because summary wins",
                notesMarkdown: "raw notes") == "Launch is imminent.")
        #expect(
            LibraryCopy.excerpt(
                summary: nil,
                enhancedNotesMarkdown: "## Decisions\n- Launch moved to July",
                notesMarkdown: "fallback") == "Decisions\nLaunch moved to July")
        #expect(
            LibraryCopy.excerpt(
                summary: "   ",
                enhancedNotesMarkdown: nil,
                notesMarkdown: "- remember the budget\n\n# Next")
                == "remember the budget\nNext")
        #expect(
            LibraryCopy.excerpt(summary: nil, enhancedNotesMarkdown: nil, notesMarkdown: "  \n")
                == nil)
    }

    @Test func libraryExcerptSkipsLeadingBlanksAndStopsAtTwoPlainLines() {
        let leading = "\n\n  \n- first real\n- second real\n- third ignored\n"
        #expect(
            LibraryCopy.excerpt(
                summary: nil, enhancedNotesMarkdown: leading, notesMarkdown: "fallback")
                == "first real\nsecond real")
        #expect(
            LibraryCopy.excerpt(
                summary: nil, enhancedNotesMarkdown: "  \n\t\n", notesMarkdown: "  \n")
                == nil)
        #expect(
            LibraryCopy.excerpt(
                summary: nil,
                enhancedNotesMarkdown: "\n\n",
                notesMarkdown: "\n# Next\n\nplain closer")
                == "Next\nplain closer")
    }

    @Test func libraryExcerptOnLongNotesMatchesTheFirstTwoPlainLines() {
        var markdown = "## Decisions\n- Launch moved to July\n"
        for index in 0..<5_000 {
            markdown += "- filler \(index) that must not appear in the card excerpt\n"
        }
        #expect(
            LibraryCopy.excerpt(
                summary: nil, enhancedNotesMarkdown: markdown, notesMarkdown: "fallback")
                == "Decisions\nLaunch moved to July")
        #expect(
            LibraryCopy.excerpt(
                summary: "Keep the summary.",
                enhancedNotesMarkdown: markdown,
                notesMarkdown: markdown) == "Keep the summary.")
    }

    @Test func libraryExcerptUsesPersistedMeetingNotesNotASourceString() throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        var meeting = Meeting.new(title: "Persisted long note", language: "en-US")
        meeting.notesMarkdown = "\n\n- first real\n- second real\n"
        for index in 0..<2_000 {
            meeting.notesMarkdown += "- stored filler \(index)\n"
        }
        meeting.enhancedNotesMarkdown = "  \n"
        try db.save(meeting)

        let loaded = try #require(try db.fetchMeeting(id: meeting.id))
        #expect(loaded.notesMarkdown.count > 20_000)
        #expect(
            LibraryCopy.excerpt(
                summary: loaded.summary,
                enhancedNotesMarkdown: loaded.enhancedNotesMarkdown,
                notesMarkdown: loaded.notesMarkdown)
                == "first real\nsecond real")

        var empty = Meeting.new(title: "Persisted empty", language: "en-US")
        empty.notesMarkdown = "  \n\n"
        try db.save(empty)
        let loadedEmpty = try #require(try db.fetchMeeting(id: empty.id))
        #expect(
            LibraryCopy.excerpt(
                summary: loadedEmpty.summary,
                enhancedNotesMarkdown: loadedEmpty.enhancedNotesMarkdown,
                notesMarkdown: loadedEmpty.notesMarkdown) == nil)
    }

    @Test func libraryExcerptDoesNotParsePastTheTwoShownLines() {
        var markdown = "Hello\nWorld\n"
        markdown += String(repeating: "- filler line for the card excerpt budget\n", count: 20_000)
        let clock = ContinuousClock()
        func nanos(_ body: () -> Void) -> Int64 {
            (0..<5).map { _ in
                let duration = clock.measure(body)
                let parts = duration.components
                return parts.seconds * 1_000_000_000 + parts.attoseconds / 1_000_000_000
            }.min() ?? Int64.max
        }
        var fullBlocks = 0
        let fullNs = nanos { fullBlocks = MarkdownParser.parse(markdown).count }
        var excerpt: String?
        let excerptNs = nanos {
            excerpt = LibraryCopy.excerpt(
                summary: nil, enhancedNotesMarkdown: markdown, notesMarkdown: "")
        }
        let prefix = MarkdownParser.parse(markdown, maxBlocks: 2)
        #expect(fullBlocks == 20_002)
        #expect(excerpt == "Hello\nWorld")
        #expect(prefix.blocks.count == 2)
        #expect(prefix.linesVisited == 2)
        #expect(
            excerptNs * 8 < fullNs,
            "excerpt \(excerptNs)ns vs full parse \(fullNs)ns over \(fullBlocks) blocks")
    }

    @Test func libraryMetaKeepsRealStatusFolderDurationAndDate() {
        let date = Date(timeIntervalSince1970: 1_750_968_000)
        let parts = LibraryCopy.metaParts(
            status: "Recording",
            folder: "Engineering",
            duration: "1:15",
            date: date)
        #expect(Array(parts.prefix(3)) == ["Recording", "Engineering", "1:15"])
        #expect(parts.count == 4)
        #expect(parts.last == LibraryCopy.dateLabel(date))
        #expect(
            LibraryCopy.metaParts(status: nil, folder: nil, duration: nil, date: date)
                == [LibraryCopy.dateLabel(date)])
    }

    @Test func destinationChromeMatchesTheContract() {
        // Human-approved Home unification (2026-09-05): sidebar app destinations
        // are Home + Dictation. Meetings/Notes/Files stay on allCases as leftover
        // transient routes for fixtures; Settings stays out of the library list.
        // Previous assertion expected five sidebar titles; that UI contract was
        // replaced, not weakened — see appSidebarDestinationsAreHomeAndDictationOnly.
        #expect(SidebarDestination.appDestinations.map(\.title) == [
            "Home", "Dictation",
        ])
        #expect(SidebarDestination.allCases.map(\.title) == [
            "Home", "Dictation", "Meetings", "Notes", "Files", "Settings",
        ])
        #expect(SidebarDestination.home.icon == "house.fill")
        #expect(SidebarDestination.dictation.icon == "mic.fill")
        #expect(SidebarDestination.meetings.icon == "calendar")
        #expect(SidebarDestination.notes.icon == "square.and.pencil")
        #expect(SidebarDestination.files.icon == "folder.fill")
        #expect(SidebarDestination.settings.icon == "gearshape")
        #expect(AppNavigation.showsAppSidebar(for: .home))
        #expect(!AppNavigation.showsAppSidebar(for: .settings))
    }

    @Test func settingsHidesInspectorAtEveryWidthEvenWithAMeetingSelected() {
        for width: CGFloat in [960, 1120, 1280, 1440] {
            #expect(
                AppNavigation.inspectorKind(
                    destination: .settings,
                    dictationShowsInspector: true,
                    windowWidth: width,
                    meetingSelected: true) == .none)
            #expect(
                AppNavigation.inspectorKind(
                    destination: .settings,
                    dictationShowsInspector: false,
                    windowWidth: width) == .none)
        }
    }

    @Test func openingSettingsSnapshotsTheLastAppRouteWithoutClearingIt() {
        let snap = AppNavigation.SettingsReturn.snapshot(
            destination: .meetings,
            selectedMeetingID: "m1",
            selectedFolderID: "eng")
        #expect(snap?.destination == .meetings)
        #expect(snap?.selectedMeetingID == "m1")
        #expect(snap?.selectedFolderID == "eng")
        #expect(snap?.libraryFilter == .all)
    }

    @Test func openingSettingsAgainDoesNotReplaceTheReturnSnapshot() {
        let first = AppNavigation.SettingsReturn.snapshot(
            destination: .home, selectedMeetingID: "m1", selectedFolderID: nil)
        let alreadyThere = AppNavigation.SettingsReturn.snapshot(
            destination: .settings, selectedMeetingID: "m1", selectedFolderID: nil)
        #expect(first != nil)
        #expect(alreadyThere == nil)
    }

    @Test func leavingSettingsRestoresDestinationMeetingAndFolder() {
        let snap = AppNavigation.SettingsReturn(
            destination: .notes, selectedMeetingID: "note-1", selectedFolderID: nil)
        let restored = AppNavigation.leaveSettings(snap)
        #expect(restored.destination == .notes)
        #expect(restored.selectedMeetingID == "note-1")
        #expect(restored.selectedFolderID == nil)
        #expect(restored.libraryFilter == .all)
        #expect(restored.destination != .settings)
    }

    @Test func leavingSettingsWithoutASnapshotReturnsHome() {
        let restored = AppNavigation.leaveSettings(nil)
        #expect(restored.destination == .home)
        #expect(restored.selectedMeetingID == nil)
        #expect(restored.selectedFolderID == nil)
        #expect(restored.libraryFilter == .all)
    }

    @Test func openingAMeetingKeepsTheSourceDestinationHighlighted() {
        #expect(
            AppNavigation.highlight(destination: .home, selectedFolderID: nil)
                == .destination(.home))
        #expect(
            AppNavigation.highlight(destination: .dictation, selectedFolderID: nil)
                == .destination(.dictation))
        #expect(
            AppNavigation.isPrimaryActive(
                item: .home, destination: .home, selectedFolderID: nil))
        #expect(
            !AppNavigation.isPrimaryActive(
                item: .dictation, destination: .home, selectedFolderID: nil))
        #expect(
            AppNavigation.isPrimaryActive(
                item: .dictation, destination: .dictation, selectedFolderID: nil))
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

    @Test func notesAndFilesSearchUseDatabaseSemanticsIncludingTranscript() throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        var noted = Meeting.new(title: "Untitled note", language: "en-US")
        noted.notesMarkdown = "ship the shell"
        try db.save(noted)
        try db.save(
            TranscriptSegment.new(
                meetingID: noted.id, channel: .system, speaker: "Them",
                text: "alpha-unique-token", startSeconds: 0, endSeconds: 2, isFinal: true))

        var recordingOnly = Meeting.new(title: "Recorded", language: "en-US")
        recordingOnly.audioMicPath = "/tmp/mic.m4a"
        try db.save(recordingOnly)
        try db.save(
            TranscriptSegment.new(
                meetingID: recordingOnly.id, channel: .mic, speaker: "Me",
                text: "alpha-unique-token", startSeconds: 0, endSeconds: 2, isFinal: true))

        var titled = Meeting.new(title: "Standup", language: "auto")
        titled.notesMarkdown = "ship notes"
        try db.save(titled)

        #expect(MeetingLibrary.searchNotes(query: "alpha-unique-token", database: db).map(\.id) == [noted.id])
        #expect(
            MeetingLibrary.searchRecordings(query: "alpha-unique-token", database: db).map(\.id)
                == [recordingOnly.id])
        #expect(MeetingLibrary.searchNotes(query: "SHIP notes", database: db).map(\.title) == ["Standup"])
        #expect(MeetingLibrary.searchNotes(query: "  ", database: db).isEmpty)
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

    @Test func selectedMeetingOpensTheMeetingInspector() {
        let destinations: [SidebarDestination] = [.home, .meetings, .notes, .files]
        for destination in destinations {
            for width: CGFloat in [960, 1120, 1280] {
                #expect(
                    AppNavigation.inspectorKind(
                        destination: destination,
                        dictationShowsInspector: false,
                        windowWidth: width,
                        meetingSelected: true) == .meeting)
            }
        }
    }

    @Test func dictationDestinationWinsOverASelectedMeeting() {
        #expect(
            AppNavigation.inspectorKind(
                destination: .dictation,
                dictationShowsInspector: false,
                windowWidth: 1440,
                meetingSelected: true) == .dictationIdle)
        #expect(
            AppNavigation.inspectorKind(
                destination: .dictation,
                dictationShowsInspector: true,
                windowWidth: 1440,
                meetingSelected: true) == .dictationLive)
        #expect(
            AppNavigation.inspectorKind(
                destination: .dictation,
                dictationShowsInspector: true,
                windowWidth: 1120,
                meetingSelected: true) == .dictationLive)
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

    @Test func liveDictationInspectorIsAvailableAtEveryWidth() {
        for width: CGFloat in [960, 1120, 1279, 1280, 1440] {
            #expect(
                AppNavigation.inspectorKind(
                    destination: .dictation,
                    dictationShowsInspector: true,
                    windowWidth: width) == .dictationLive)
        }
    }

    @Test func inspectorToggleStaysInLibraryTitlebars() {
        for destination in SidebarDestination.appDestinations {
            #expect(AppNavigation.showsInspectorToggle(destination: destination))
        }
        #expect(!AppNavigation.showsInspectorToggle(destination: .settings))
        #expect(AppNavigation.inspectorToggleEnabled(kind: .dictationIdle))
        #expect(AppNavigation.inspectorToggleEnabled(kind: .dictationLive))
        #expect(AppNavigation.inspectorToggleEnabled(kind: .meeting))
        #expect(!AppNavigation.inspectorToggleEnabled(kind: .none))
    }

    @Test func librarySearchPendingIsNotAnEmptyState() {
        #expect(
            LibraryListPhase.resolve(isEmpty: false, isSearching: true, searchInFlight: true)
                == .rows)
        #expect(
            LibraryListPhase.resolve(isEmpty: true, isSearching: true, searchInFlight: true)
                == .pending)
        #expect(
            LibraryListPhase.resolve(isEmpty: true, isSearching: true, searchInFlight: false)
                == .empty)
        #expect(
            LibraryListPhase.resolve(isEmpty: true, isSearching: false, searchInFlight: false)
                == .empty)
    }

    @Test func mainWindowKeepsTheInspectorToggleForLibraryDestinations() throws {
        let source = try granipaSource("Sources/Granipa/UI/MainWindow.swift")
        #expect(source.contains("showsInspectorToggle(destination:"))
        #expect(source.contains("inspectorToggleEnabled(kind:"))
        #expect(source.contains("kind: inspectorKind"))
        #expect(!source.contains("if inspectorKind != .none"))
        #expect(!source.contains("hasContent: inspectorKind != .none"))
        #expect(!source.contains("value: inspectorPresentation"))
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

    @Test func leftoverLibraryRoutesHighlightHomeNotRemovedSidebarRows() {
        for leftover in [SidebarDestination.meetings, .notes, .files] {
            #expect(
                AppNavigation.resolvedAppDestination(leftover) == .home)
            #expect(
                AppNavigation.highlight(destination: leftover, selectedFolderID: nil)
                    == .destination(.home))
            #expect(
                AppNavigation.isPrimaryActive(
                    item: .home, destination: leftover, selectedFolderID: nil))
            #expect(
                !AppNavigation.isPrimaryActive(
                    item: leftover, destination: leftover, selectedFolderID: nil))
        }
    }

    @Test func homeFilterDefaultsToAllAndLeftoverRoutesMapToType() {
        #expect(HomeLibraryFilter.allCases.map(\.title) == ["All", "Notes", "Recordings"])
        #expect(
            AppNavigation.activeLibraryFilter(destination: .home, stored: .all) == .all)
        #expect(
            AppNavigation.activeLibraryFilter(destination: .home, stored: .notes) == .notes)
        #expect(
            AppNavigation.activeLibraryFilter(destination: .notes, stored: .all) == .notes)
        #expect(
            AppNavigation.activeLibraryFilter(destination: .files, stored: .all)
                == .recordings)
        #expect(
            AppNavigation.activeLibraryFilter(destination: .meetings, stored: .notes)
                == .all)
        #expect(
            AppNavigation.activeLibraryFilter(destination: .dictation, stored: .notes)
                == .notes)
    }

    @Test func revealHomeAndDictationKeepTheCurrentFilter() {
        let home = AppNavigation.reveal(.home, currentFilter: .recordings)
        #expect(home.destination == .home)
        #expect(home.filter == .recordings)
        let dictation = AppNavigation.reveal(.dictation, currentFilter: .notes)
        #expect(dictation.destination == .dictation)
        #expect(dictation.filter == .notes)
    }

    @Test func leftoverRevealsCanonicalizeOntoHomeFilters() {
        let notes = AppNavigation.reveal(.notes, currentFilter: .all)
        #expect(notes.destination == .home)
        #expect(notes.filter == .notes)
        let files = AppNavigation.reveal(.files, currentFilter: .notes)
        #expect(files.destination == .home)
        #expect(files.filter == .recordings)
        let meetings = AppNavigation.reveal(.meetings, currentFilter: .notes)
        #expect(meetings.destination == .home)
        #expect(meetings.filter == .all)
    }

    @Test func selectingAFilterFromALeftoverRouteReturnsToHome() {
        let next = AppNavigation.selectingFilter(.recordings, destination: .notes)
        #expect(next.destination == .home)
        #expect(next.filter == .recordings)
        let alreadyHome = AppNavigation.selectingFilter(.notes, destination: .home)
        #expect(alreadyHome.destination == .home)
        #expect(alreadyHome.filter == .notes)
    }

    @Test func collectionsStayOnHomeAndKeepTheTypeFilter() {
        #expect(AppNavigation.folderRevealDestination == .home)
        #expect(AppNavigation.folderRevealDestination != .meetings)
        let highlight = AppNavigation.highlight(
            destination: .home, selectedFolderID: "eng")
        #expect(highlight == .folder("eng"))
        #expect(
            !AppNavigation.isPrimaryActive(
                item: .home, destination: .home, selectedFolderID: "eng"))
        #expect(
            AppNavigation.activeLibraryFilter(destination: .home, stored: .notes) == .notes)
    }

    @Test func settingsReturnRetainsLibraryFilterAcrossMeetingAndSettings() {
        let snap = AppNavigation.SettingsReturn.snapshot(
            destination: .home,
            selectedMeetingID: "m-open",
            selectedFolderID: "eng",
            libraryFilter: .recordings)
        #expect(snap?.libraryFilter == .recordings)
        let restored = AppNavigation.leaveSettings(snap)
        #expect(restored.destination == .home)
        #expect(restored.selectedMeetingID == "m-open")
        #expect(restored.selectedFolderID == "eng")
        #expect(restored.libraryFilter == .recordings)
    }

    @Test func calendarCardStaysOnUnfilteredHomeAllOnly() {
        #expect(
            AppNavigation.showsHomeCalendarCard(
                filter: .all, isSearching: false, hasFolder: false))
        #expect(
            !AppNavigation.showsHomeCalendarCard(
                filter: .notes, isSearching: false, hasFolder: false))
        #expect(
            !AppNavigation.showsHomeCalendarCard(
                filter: .recordings, isSearching: false, hasFolder: false))
        #expect(
            !AppNavigation.showsHomeCalendarCard(
                filter: .all, isSearching: true, hasFolder: false))
        #expect(
            !AppNavigation.showsHomeCalendarCard(
                filter: .all, isSearching: false, hasFolder: true))
    }

    @Test func shownMeetingsIntersectFolderAndTypeFilter() {
        var noteInFolder = Meeting.new(title: "Note in folder", language: "auto")
        noteInFolder.folderID = "eng"
        noteInFolder.notesMarkdown = "ship"
        var recordingInFolder = Meeting.new(title: "Rec in folder", language: "auto")
        recordingInFolder.folderID = "eng"
        recordingInFolder.audioMicPath = "/tmp/mic.m4a"
        var noteLoose = Meeting.new(title: "Loose note", language: "auto")
        noteLoose.notesMarkdown = "ship"
        var recordingLoose = Meeting.new(title: "Loose rec", language: "auto")
        recordingLoose.audioSystemPath = "/tmp/sys.m4a"
        let all = [noteInFolder, recordingInFolder, noteLoose, recordingLoose]

        #expect(
            Set(MeetingLibrary.shown(in: all, filter: .all, folderID: nil).map(\.title))
                == ["Note in folder", "Rec in folder", "Loose note", "Loose rec"])
        #expect(
            Set(MeetingLibrary.shown(in: all, filter: .notes, folderID: nil).map(\.title))
                == ["Note in folder", "Loose note"])
        #expect(
            Set(
                MeetingLibrary.shown(in: all, filter: .recordings, folderID: nil).map(\.title))
                == ["Rec in folder", "Loose rec"])
        #expect(
            Set(MeetingLibrary.shown(in: all, filter: .all, folderID: "eng").map(\.title))
                == ["Note in folder", "Rec in folder"])
        #expect(
            MeetingLibrary.shown(in: all, filter: .notes, folderID: "eng").map(\.title)
                == ["Note in folder"])
        #expect(
            MeetingLibrary.shown(in: all, filter: .recordings, folderID: "eng").map(\.title)
                == ["Rec in folder"])
        #expect(MeetingLibrary.shown(in: all, filter: .notes, folderID: "prod").isEmpty)
    }

    @Test func searchUsesLiveResultsOnlyWhileSearchingAndDropsSupersededQueries() {
        let live = Meeting.new(title: "Live library", language: "auto")
        let stale = Meeting.new(title: "Stale search", language: "auto")
        #expect(!MeetingLibrary.isSearching("  \n"))
        #expect(MeetingLibrary.isSearching("ship"))
        #expect(
            MeetingLibrary.libraryBase(
                meetings: [live], searchResults: [stale], isSearching: false)
                == [live])
        #expect(
            MeetingLibrary.libraryBase(
                meetings: [live], searchResults: [stale], isSearching: true)
                == [stale])
        #expect(
            !MeetingLibrary.acceptSearch(
                finishedQuery: "old", currentQuery: "new", cancelled: false))
        #expect(
            !MeetingLibrary.acceptSearch(
                finishedQuery: "q", currentQuery: "q", cancelled: true))
        #expect(
            MeetingLibrary.acceptSearch(
                finishedQuery: "q", currentQuery: "q", cancelled: false))
    }

    @Test func emptyCopyMatchesActiveFilterFolderAndSearch() {
        let search = LibraryCopy.emptyCopy(
            isSearching: true, query: "alpha", filter: .notes, folderName: "Eng")
        #expect(search.icon == "magnifyingglass")
        #expect(search.title == "No results for \"alpha\"")
        #expect(search.message == nil)
        #expect(!search.showsQuickNote && !search.showsRecord)

        let notes = LibraryCopy.emptyCopy(
            isSearching: false, query: "", filter: .notes, folderName: nil)
        #expect(notes.title == "No notes yet")
        #expect(notes.showsQuickNote && !notes.showsRecord)

        let recordings = LibraryCopy.emptyCopy(
            isSearching: false, query: "", filter: .recordings, folderName: nil)
        #expect(recordings.title == "No recordings yet")
        #expect(!recordings.showsQuickNote && recordings.showsRecord)

        let folderNotes = LibraryCopy.emptyCopy(
            isSearching: false, query: "", filter: .notes, folderName: "Eng")
        #expect(folderNotes.title == "No notes in this folder")
        #expect(folderNotes.showsQuickNote)

        let allHome = LibraryCopy.emptyCopy(
            isSearching: false, query: "", filter: .all, folderName: nil)
        #expect(allHome.title == "No meetings yet")
        #expect(allHome.showsQuickNote && allHome.showsRecord)
    }

    @Test func homeSearchFilterAndFolderIntersectOnRealGRDB() throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let folder = Folder.new(name: "Engineering", team: nil)
        try db.save(folder)
        let otherFolder = Folder.new(name: "Other", team: nil)
        try db.save(otherFolder)

        var noteInFolder = Meeting.new(title: "Untitled note", language: "en-US")
        noteInFolder.folderID = folder.id
        noteInFolder.notesMarkdown = "shell notes"
        try db.save(noteInFolder)
        try db.save(
            TranscriptSegment.new(
                meetingID: noteInFolder.id, channel: .system, speaker: "Them",
                text: "home-unify-token", startSeconds: 0, endSeconds: 2, isFinal: true))

        var noteOtherFolder = Meeting.new(title: "Other note", language: "en-US")
        noteOtherFolder.folderID = otherFolder.id
        noteOtherFolder.notesMarkdown = "shell notes"
        try db.save(noteOtherFolder)
        try db.save(
            TranscriptSegment.new(
                meetingID: noteOtherFolder.id, channel: .mic, speaker: "Me",
                text: "home-unify-token", startSeconds: 0, endSeconds: 2, isFinal: true))

        var recordingInFolder = Meeting.new(title: "Recorded", language: "en-US")
        recordingInFolder.folderID = folder.id
        recordingInFolder.audioMicPath = "/tmp/mic.m4a"
        try db.save(recordingInFolder)
        try db.save(
            TranscriptSegment.new(
                meetingID: recordingInFolder.id, channel: .mic, speaker: "Me",
                text: "home-unify-token", startSeconds: 0, endSeconds: 2, isFinal: true))

        let searched = try db.searchMeetings(query: "home-unify-token")
        #expect(Set(searched.map(\.id)) == [
            noteInFolder.id, noteOtherFolder.id, recordingInFolder.id,
        ])
        #expect(
            MeetingLibrary.shown(in: searched, filter: .notes, folderID: folder.id).map(\.id)
                == [noteInFolder.id])
        #expect(
            MeetingLibrary.shown(
                in: searched, filter: .recordings, folderID: folder.id
            ).map(\.id) == [recordingInFolder.id])
        #expect(
            Set(
                MeetingLibrary.shown(in: searched, filter: .all, folderID: folder.id).map(\.id))
                == [noteInFolder.id, recordingInFolder.id])
    }

    @Test func homeWiresExistingNoteAndRecordingRowsNotGenericReplacements() throws {
        let home = try granipaSource("Sources/Granipa/UI/HomeView.swift")
        let main = try granipaSource("Sources/Granipa/UI/MainWindow.swift")
        let sidebar = try granipaSource("Sources/Granipa/UI/SidebarView.swift")
        #expect(home.contains("HomeLibraryFilterStrip"))
        #expect(home.contains("NotesLibraryRow"))
        #expect(home.contains("FilesLibraryRow"))
        #expect(home.contains("fileStatuses"))
        #expect(home.contains("MeetingLibrary.fileStatuses"))
        #expect(home.contains("accessibilityAddTraits(isSelected ? .isSelected : [])"))
        #expect(!home.contains("return \"Meetings\""))
        #expect(!main.contains("NotesLibraryView()"))
        #expect(!main.contains("FilesLibraryView()"))
        #expect(main.contains("HomeView()"))
        #expect(sidebar.contains("SidebarDestination.appDestinations"))
        #expect(!sidebar.contains("case .meetings"))
    }
}

private func granipaSource(_ relativePath: String) throws -> String {
    let testsFile = URL(fileURLWithPath: #filePath)
    let repo = testsFile.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repo.appendingPathComponent(relativePath), encoding: .utf8)
}
