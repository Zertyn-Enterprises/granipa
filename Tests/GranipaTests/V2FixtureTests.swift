#if DEBUG
import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct V2FixtureTests {
    private static let shellMeetingIDs = Set([
        "fixture-mtg-sync", "fixture-mtg-planning", "fixture-mtg-review",
        "fixture-mtg-quicknote", "fixture-mtg-interview", "fixture-mtg-personal",
    ])
    private static let recordedMeetingIDs = Set([
        "fixture-mtg-sync", "fixture-mtg-planning", "fixture-mtg-review",
        "fixture-mtg-interview", "fixture-mtg-personal",
    ])

    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    private func makeTempRoot(_ base: String) throws -> URL {
        let root = URL(fileURLWithPath: base)
            .appendingPathComponent("granipa-v2-fixture-tests.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func seedShell(database: AppDatabase, audioRoot: URL) throws {
        try V2FixtureSeeder.seed(.shell, into: database, audioDirectory: { meetingID in
            audioRoot.appendingPathComponent(meetingID, isDirectory: true)
        })
    }

    // MARK: argument parser

    @Test func parserWithoutTheFlagStaysOff() {
        #expect(V2FixtureRuntime.parseArguments([]) == .off)
        #expect(V2FixtureRuntime.parseArguments(["Granipa"]) == .off)
        #expect(V2FixtureRuntime.parseArguments(["-v2", "--dock", "extra"]) == .off)
    }

    @Test func parserAcceptsShellAndMany() {
        #expect(V2FixtureRuntime.parseArguments(["--v2-fixture", "shell"]) == .run(.shell))
        #expect(V2FixtureRuntime.parseArguments(["--v2-fixture", "many"]) == .run(.many))
        #expect(
            V2FixtureRuntime.parseArguments(["Granipa", "--v2-fixture", "shell", "--other"])
                == .run(.shell))
    }

    @Test func parserRefusesUnknownOrMissingFixtureName() {
        guard case .refuse = V2FixtureRuntime.parseArguments(["--v2-fixture", "sandbox"]) else {
            Issue.record("unknown fixture name must be refused")
            return
        }
        guard case .refuse = V2FixtureRuntime.parseArguments(["--v2-fixture"]) else {
            Issue.record("missing fixture name must be refused")
            return
        }
    }

    // MARK: isolated-root gate

    @Test func gateFailsClosedWithoutAnIsolatedRoot() throws {
        let safeRoot = try makeTempRoot("/private/tmp")
        defer { try? FileManager.default.removeItem(at: safeRoot) }
        let isolated = ["CFFIXED_USER_HOME": safeRoot.path]

        #expect(V2FixtureRuntime.resolve(arguments: [], environment: [:]) == .off)
        #expect(V2FixtureRuntime.resolve(arguments: [], environment: isolated) == .off)

        guard case .refuse = V2FixtureRuntime.resolve(
            arguments: ["--v2-fixture", "shell"], environment: [:])
        else {
            Issue.record("fixture request without CFFIXED_USER_HOME must be refused")
            return
        }
        guard case .refuse = V2FixtureRuntime.resolve(
            arguments: ["--v2-fixture", "shell"],
            environment: ["CFFIXED_USER_HOME": safeRoot.path + "/.."])
        else {
            Issue.record("parent of the temp root must be refused")
            return
        }
    }

    @Test func gateRefusesRootsOutsideTheSystemTempArea() {
        for root in [
            "", "  ", "~/tmp", "/Users/Shared", NSHomeDirectory(),
            "/private/tmp", "/tmp", "/private/tmpfoo/x", "/private/tmp/../Users/x",
            "/var/folders/zz/xy/T/",
        ] {
            #expect(!V2FixtureRuntime.isIsolatedTempRoot(root), "refused unexpectedly: \(root)")
        }
    }

    @Test func gateAcceptsCanonicalAndSymlinkedTempRoots() throws {
        let root = try makeTempRoot("/private/tmp")
        defer { try? FileManager.default.removeItem(at: root) }
        let symlinkForm = String(root.path.dropFirst("/private".count))

        #expect(V2FixtureRuntime.isIsolatedTempRoot(root.path))
        #expect(V2FixtureRuntime.isIsolatedTempRoot(symlinkForm))
        #expect(
            V2FixtureRuntime.resolve(
                arguments: ["--v2-fixture", "many"],
                environment: ["CFFIXED_USER_HOME": root.path]) == .run(.many))
    }

    // MARK: shell seed

    @Test func shellSeedCountsIDsAndFolderClassification() throws {
        let db = try makeDatabase()
        let audioRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-v2-fixture-tests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: audioRoot) }
        try seedShell(database: db, audioRoot: audioRoot)

        let meetings = try db.fetchMeetings()
        #expect(meetings.count == 6)
        #expect(Set(meetings.map(\.id)) == Self.shellMeetingIDs)

        #expect(try db.fetchFolders().map(\.id) == [
            "fixture-folder-team", "fixture-folder-projects", "fixture-folder-personal",
        ])
        #expect(try db.folderMeetingCounts() == [
            "fixture-folder-team": 2, "fixture-folder-projects": 2,
            "fixture-folder-personal": 1,
        ])

        let notesIDs = Set(
            meetings.filter {
                !$0.notesMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }.map(\.id))
        #expect(
            notesIDs == ["fixture-mtg-sync", "fixture-mtg-quicknote", "fixture-mtg-interview"])
        let recordingIDs = Set(
            meetings.filter { $0.audioMicPath != nil || $0.audioSystemPath != nil }.map(\.id))
        #expect(recordingIDs == Self.recordedMeetingIDs)
    }

    @Test func shellSeedSearchMatchesTheRealDatabaseSemantics() throws {
        let db = try makeDatabase()
        let audioRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-v2-fixture-tests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: audioRoot) }
        try seedShell(database: db, audioRoot: audioRoot)

        #expect(try db.searchMeetings(query: "milestone").map(\.id) == ["fixture-mtg-sync"])
        #expect(try db.searchMeetings(query: "checkpoint").map(\.id) == ["fixture-mtg-planning"])
        #expect(try db.searchMeetings(query: "contrast").map(\.id) == ["fixture-mtg-review"])
        #expect(
            Set(try db.searchMeetings(query: "workshop").map(\.id))
                == ["fixture-mtg-quicknote", "fixture-mtg-interview"])
    }

    @Test func shellSeedTranscriptIsFinalAndHonest() throws {
        let db = try makeDatabase()
        let audioRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-v2-fixture-tests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: audioRoot) }
        try seedShell(database: db, audioRoot: audioRoot)

        let segments = try db.fetchSegments(meetingID: "fixture-mtg-sync", finalOnly: true)
        #expect(segments.count == 6)
        let allFinal = segments.allSatisfy(\.isFinal)
        #expect(allFinal)
        #expect(segments.map(\.speaker) == [
            "Me", "Speaker 1", "Me", "Speaker 2", "Me", "Speaker 1",
        ])
        #expect(segments.map(\.channel) == [.mic, .system, .mic, .system, .mic, .system])

        let allSegmentCounts = try db.fetchMeetings().map { meeting in
            try db.fetchSegments(meetingID: meeting.id).count
        }
        #expect(allSegmentCounts.sorted() == [0, 0, 2, 3, 4, 6])

        for meeting in try db.fetchMeetings() {
            #expect(meeting.summary == nil)
            #expect(meeting.enhancedNotesMarkdown == nil)
            #expect(meeting.actionItemsJSON == nil)
            #expect(meeting.emailDraft == nil)
        }
    }

    @Test func shellSeedWritesTinyFilesOnlyUnderTheAudioRoot() throws {
        let db = try makeDatabase()
        let audioRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-v2-fixture-tests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: audioRoot) }
        try seedShell(database: db, audioRoot: audioRoot)

        let meetings = try db.fetchMeetings()
        for meeting in meetings {
            let paths = [meeting.audioMicPath, meeting.audioSystemPath].compactMap { $0 }
            #expect(paths.allSatisfy { $0.hasPrefix(audioRoot.path) })
            if Self.recordedMeetingIDs.contains(meeting.id) {
                #expect(paths.count == 2)
                for path in paths {
                    let size = try FileManager.default.attributesOfItem(atPath: path)[.size]
                    #expect((size as? Int ?? Int.max) < 1_024)
                }
            } else {
                #expect(paths.isEmpty)
            }
        }
    }

    @Test func seedingTwiceLeavesOneDeterministicCopy() throws {
        let db = try makeDatabase()
        let audioRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-v2-fixture-tests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: audioRoot) }
        try seedShell(database: db, audioRoot: audioRoot)
        try seedShell(database: db, audioRoot: audioRoot)

        #expect(try db.fetchMeetings().count == 6)
        #expect(try db.fetchFolders().count == 3)
        #expect(try db.fetchSegments(meetingID: "fixture-mtg-sync").count == 6)
    }

    @Test func shellSeedIsIdenticalAcrossDatabases() throws {
        let audioRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-v2-fixture-tests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: audioRoot) }
        let first = try makeDatabase()
        try seedShell(database: first, audioRoot: audioRoot)
        let second = try makeDatabase()
        try seedShell(database: second, audioRoot: audioRoot)

        let firstMeetings = try first.fetchMeetings()
        let secondMeetings = try second.fetchMeetings()
        #expect(firstMeetings == secondMeetings)
        let firstFolders = try first.fetchFolders()
        let secondFolders = try second.fetchFolders()
        #expect(firstFolders == secondFolders)
        let firstSegments = try first.fetchSegments(meetingID: "fixture-mtg-sync")
        let secondSegments = try second.fetchSegments(meetingID: "fixture-mtg-sync")
        #expect(firstSegments == secondSegments)
    }

    // MARK: many seed

    @Test func manySeedsExactlyTwoHundredMeetingsAndNothingElse() throws {
        let db = try makeDatabase()
        try V2FixtureSeeder.seed(.many, into: db, audioDirectory: { _ in
            struct UnexpectedAudioWrite: Error {}
            throw UnexpectedAudioWrite()
        })
        try V2FixtureSeeder.seed(.many, into: db, audioDirectory: { _ in
            struct UnexpectedAudioWrite: Error {}
            throw UnexpectedAudioWrite()
        })

        let meetings = try db.fetchMeetings()
        #expect(meetings.count == 200)
        #expect(meetings.first?.id == "fixture-many-200")
        #expect(meetings.last?.id == "fixture-many-001")
        #expect(meetings.allSatisfy { $0.status == .ready })
        #expect(Set(meetings.map(\.title)).count == 200)
        #expect(try db.fetchFolders().isEmpty)
        #expect(try db.fetchSegments(meetingID: "fixture-many-001").isEmpty)
    }

    // MARK: onboarding defaults

    @Test func onboardingIsCompletedInTheInjectedDefaultsDomain() {
        guard let suite = UserDefaults(suiteName: "v2-fixture-tests") else {
            Issue.record("defaults suite could not be created")
            return
        }
        defer { suite.removePersistentDomain(forName: "v2-fixture-tests") }

        V2FixtureSeeder.markOnboardingComplete(in: suite)

        #expect(suite.bool(forKey: "onboardingCompleted"))
    }
}
#endif
