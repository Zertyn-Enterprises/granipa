#if DEBUG
import Foundation

/// Deterministic seed data for `--v2-fixture`. Every row carries a fixed ID
/// and a date derived from `referenceDate`, so screenshots and scroll profiles
/// are reproducible. Content stays honest: real transcript-style segments and
/// human-style notes only — no invented AI output, metrics, or providers.
enum V2FixtureSeeder {
    /// 2026-06-15T09:00:00Z.
    static let referenceDate = Date(timeIntervalSince1970: 1_781_514_000)

    /// Marks onboarding as complete in the given defaults domain. The fixture
    /// process passes `UserDefaults.standard`, which CFFIXED_USER_HOME has
    /// already redirected into the throwaway home.
    static func markOnboardingComplete(in defaults: UserDefaults) {
        defaults.set(true, forKey: "onboardingCompleted")
    }

    static func seed(
        _ fixture: V2Fixture,
        into database: AppDatabase,
        audioDirectory: (String) throws -> URL
    ) throws {
        switch fixture {
        case .shell: try seedShell(into: database, audioDirectory: audioDirectory)
        case .many: try seedMany(into: database)
        }
    }

    // MARK: shell — one screen-worth of honest data for every destination

    private static func seedShell(
        into database: AppDatabase,
        audioDirectory: (String) throws -> URL
    ) throws {
        for folder in [
            Folder(id: "fixture-folder-team", name: "Team Meetings", team: nil, position: 0),
            Folder(id: "fixture-folder-projects", name: "Projects", team: nil, position: 1),
            Folder(id: "fixture-folder-personal", name: "Personal", team: nil, position: 2),
        ] {
            try database.save(folder)
        }

        var sync = meeting(
            id: "fixture-mtg-sync", title: "Weekly Team Sync", folderID: "fixture-folder-team",
            dayOffset: 0, duration: 2_700, notes: """
                Agenda:
                - Release timeline
                - Review step

                Follow-ups live in the transcript.
                """)
        try attachAudio(to: &sync, audioDirectory: audioDirectory)
        try database.save(sync)
        try saveSegments(
            [
                (.mic, "Me", "Let's start with the timeline for the next release."),
                (.system, "Speaker 1", "We are on track, but the review step needs two more days."),
                (.mic, "Me", "Okay. I will update the milestone dates today."),
                (.system, "Speaker 2", "The staging deploy is blocked on the config change."),
                (.mic, "Me", "Noted. I will follow up after the call."),
                (.system, "Speaker 1", "Thanks everyone. Same time next week."),
            ], meetingID: sync.id, into: database)

        var planning = meeting(
            id: "fixture-mtg-planning", title: "Product Planning",
            folderID: "fixture-folder-projects", dayOffset: -1, duration: 1_800, notes: "")
        try attachAudio(to: &planning, audioDirectory: audioDirectory)
        try database.save(planning)
        try saveSegments(
            [
                (.system, "Speaker 1", "The roadmap draft covers the next two quarters."),
                (.mic, "Me", "Let's keep the scope small for the first release."),
                (.system, "Speaker 2", "Agreed. I will trim the checklist."),
                (.mic, "Me", "We can revisit the scope after the beta checkpoint."),
            ], meetingID: planning.id, into: database)

        var review = meeting(
            id: "fixture-mtg-review", title: "Design Review", folderID: "fixture-folder-team",
            dayOffset: -2, duration: 1_200, notes: "")
        try attachAudio(to: &review, audioDirectory: audioDirectory)
        try database.save(review)
        try saveSegments(
            [
                (.mic, "Me", "The new sidebar layout reads much better."),
                (.system, "Speaker 1", "Let's check the contrast on the dark theme."),
            ], meetingID: review.id, into: database)

        let quickNote = meeting(
            id: "fixture-mtg-quicknote", title: "Workshop Ideas", folderID: nil,
            dayOffset: -3, duration: nil, notes: """
                Workshop ideas:
                - Session about note-taking templates
                - Invite the design team
                """)
        try database.save(quickNote)

        var interview = meeting(
            id: "fixture-mtg-interview", title: "User Interview",
            folderID: "fixture-folder-projects", dayOffset: -4, duration: 3_600, notes: """
                Interview notes:
                - Weekly summaries workflow
                - Mentioned the workshop idea for templates
                """)
        try attachAudio(to: &interview, audioDirectory: audioDirectory)
        try database.save(interview)
        try saveSegments(
            [
                (.system, "Speaker 1", "I mostly use it for weekly summaries."),
                (.mic, "Me", "How long does that take you?"),
                (.system, "Speaker 1", "About ten minutes, sometimes less."),
            ], meetingID: interview.id, into: database)

        // Recorded but never transcribed: keeps the "No transcript" empty
        // state honest in screenshots.
        var personal = meeting(
            id: "fixture-mtg-personal", title: "Budget Check-In",
            folderID: "fixture-folder-personal", dayOffset: -5, duration: 900, notes: "")
        try attachAudio(to: &personal, audioDirectory: audioDirectory)
        try database.save(personal)
    }

    // MARK: many — exactly 200 rows for LazyVStack scroll profiling

    private static func seedMany(into database: AppDatabase) throws {
        for index in 1...200 {
            let number = String(format: "%03d", index)
            var meeting = Meeting.new(title: "Meeting \(number)", language: "en-US")
            meeting.id = "fixture-many-\(number)"
            meeting.createdAt = referenceDate.addingTimeInterval(TimeInterval(index - 1) * 1_800)
            try database.save(meeting)
        }
    }

    // MARK: helpers

    private static func meeting(
        id: String,
        title: String,
        folderID: String?,
        dayOffset: TimeInterval,
        duration: TimeInterval?,
        notes: String
    ) -> Meeting {
        var meeting = Meeting.new(title: title, language: "en-US")
        meeting.id = id
        meeting.createdAt = referenceDate.addingTimeInterval(dayOffset * 86_400)
        if let duration {
            meeting.startedAt = meeting.createdAt
            meeting.endedAt = meeting.createdAt.addingTimeInterval(duration)
        }
        meeting.folderID = folderID
        meeting.notesMarkdown = notes
        return meeting
    }

    /// Writes tiny placeholder files so the Files destination has real rows
    /// with real sizes. They are not playable audio and nothing claims they
    /// are; no play control exists in this slice.
    private static func attachAudio(
        to meeting: inout Meeting,
        audioDirectory: (String) throws -> URL
    ) throws {
        let dir = try audioDirectory(meeting.id)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = Data("granipa fixture audio placeholder".utf8)
        for name in ["mic.m4a", "system.m4a"] {
            let url = dir.appendingPathComponent(name)
            try payload.write(to: url)
            if name == "mic.m4a" { meeting.audioMicPath = url.path }
            else { meeting.audioSystemPath = url.path }
        }
    }

    private static func saveSegments(
        _ segments: [(channel: AudioChannel, speaker: String, text: String)],
        meetingID: String,
        into database: AppDatabase
    ) throws {
        for (index, segment) in segments.enumerated() {
            let start = TimeInterval(index) * 4.2
            try database.save(
                TranscriptSegment(
                    id: "fixture-seg-\(meetingID)-\(index + 1)",
                    meetingID: meetingID,
                    channel: segment.channel,
                    speaker: segment.speaker,
                    text: segment.text,
                    startSeconds: start,
                    endSeconds: start + 4.0,
                    isFinal: true))
        }
    }
}
#endif
