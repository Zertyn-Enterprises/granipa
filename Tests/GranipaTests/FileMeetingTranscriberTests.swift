import Foundation
import GRDB
import Testing

@testable import Granipa

/// Serialized because several of these paths persist `lastSpeechLocale` in
/// the process-global `UserDefaults.standard`; parallel mutation would race.
@Suite(.serialized) struct FileMeetingTranscriberTests {
    @Test func missingFilesLeaveNoSegments() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "T", language: "en-US")
        try db.save(meeting)
        let missing = URL(fileURLWithPath: "/tmp/granipa-no-such-\(UUID().uuidString).m4a")
        let boundary = FileMeetingTranscriber.Boundary(
            installModel: { _ in },
            analyzeChannel: { _ in [] })

        let outcome = await FileMeetingTranscriber.transcribe(
            micURL: missing,
            systemURL: missing,
            meetingID: meeting.id,
            language: "en-US",
            database: db,
            boundary: boundary
        ).outcome

        // Missing audio means "nothing to transcribe", not a failure.
        #expect(outcome == .completed(localeID: "en-US"))
        #expect((try db.fetchSegments(meetingID: meeting.id)).isEmpty)
    }

    @Test func modelInstallFailureIsReported() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "T", language: "en-US")
        try db.save(meeting)
        let missing = URL(fileURLWithPath: "/tmp/granipa-no-such-\(UUID().uuidString).m4a")
        let boundary = FileMeetingTranscriber.Boundary(
            installModel: { _ in throw TranscriptionError.notAvailable },
            analyzeChannel: { _ in [] })

        let outcome = await FileMeetingTranscriber.transcribe(
            micURL: missing,
            systemURL: missing,
            meetingID: meeting.id,
            language: "en-US",
            database: db,
            boundary: boundary
        ).outcome

        #expect(outcome == .failed(.modelInstall(localeID: "en-US")))
        #expect((try db.fetchSegments(meetingID: meeting.id)).isEmpty)
    }

    @Test func channelFailureKeepsWorkingChannelAndIsReported() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "T", language: "en-US")
        try db.save(meeting)
        let micURL = try makeAudioFixture()
        let systemURL = try makeAudioFixture()
        defer {
            try? FileManager.default.removeItem(at: micURL)
            try? FileManager.default.removeItem(at: systemURL)
        }
        let boundary = FileMeetingTranscriber.Boundary(
            installModel: { _ in },
            analyzeChannel: { analysis in
                if analysis.channel == .mic {
                    throw TranscriptionError.noAudioFormat
                }
                return [
                    TranscriptSegment.new(
                        meetingID: analysis.meetingID,
                        channel: analysis.channel,
                        speaker: "Them",
                        text: "hello",
                        startSeconds: 0,
                        endSeconds: 1,
                        isFinal: true)
                ]
            })

        let outcome = await FileMeetingTranscriber.transcribe(
            micURL: micURL,
            systemURL: systemURL,
            meetingID: meeting.id,
            language: "en-US",
            database: db,
            boundary: boundary
        ).outcome

        #expect(outcome == .failed(.channels([.mic], localeID: "en-US")))
        let segments = try db.fetchSegments(meetingID: meeting.id)
        #expect(segments.map(\.channel) == [.system])
    }

    @Test func bothChannelFailuresAreReportedInMicSystemOrder() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "T", language: "en-US")
        try db.save(meeting)
        let micURL = try makeAudioFixture()
        let systemURL = try makeAudioFixture()
        defer {
            try? FileManager.default.removeItem(at: micURL)
            try? FileManager.default.removeItem(at: systemURL)
        }
        let boundary = FileMeetingTranscriber.Boundary(
            installModel: { _ in },
            analyzeChannel: { _ in throw TranscriptionError.noAudioFormat })

        let outcome = await FileMeetingTranscriber.transcribe(
            micURL: micURL,
            systemURL: systemURL,
            meetingID: meeting.id,
            language: "en-US",
            database: db,
            boundary: boundary
        ).outcome

        // Both channels ran and both failures surfaced, mic first.
        #expect(outcome == .failed(.channels([.mic, .system], localeID: "en-US")))
        #expect((try db.fetchSegments(meetingID: meeting.id)).isEmpty)
    }

    @Test func nearEmptyFileIsSkippedNotAChannelFailure() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "T", language: "en-US")
        try db.save(meeting)
        // 2048 bytes is the "no real audio" cutoff: skipped outright, so it
        // must not appear in the failure list even when analysis would throw.
        let micURL = try makeAudioFixture(byteCount: 2_048)
        let systemURL = try makeAudioFixture()
        defer {
            try? FileManager.default.removeItem(at: micURL)
            try? FileManager.default.removeItem(at: systemURL)
        }
        let boundary = FileMeetingTranscriber.Boundary(
            installModel: { _ in },
            analyzeChannel: { _ in throw TranscriptionError.noAudioFormat })

        let outcome = await FileMeetingTranscriber.transcribe(
            micURL: micURL,
            systemURL: systemURL,
            meetingID: meeting.id,
            language: "en-US",
            database: db,
            boundary: boundary
        ).outcome

        #expect(outcome == .failed(.channels([.system], localeID: "en-US")))
        #expect((try db.fetchSegments(meetingID: meeting.id)).isEmpty)
    }

    @Test func partialChannelFailureLeavesLocaleHintToProbes() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "T", language: "en-US")
        try db.save(meeting)
        let micURL = try makeAudioFixture()
        let systemURL = try makeAudioFixture()
        defer {
            try? FileManager.default.removeItem(at: micURL)
            try? FileManager.default.removeItem(at: systemURL)
        }
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "lastSpeechLocale")
        defaults.set("fr-FR", forKey: "lastSpeechLocale")
        defer { restoreLastSpeechLocale(previous) }
        let boundary = FileMeetingTranscriber.Boundary(
            installModel: { _ in },
            analyzeChannel: { analysis in
                if analysis.channel == .mic {
                    throw TranscriptionError.noAudioFormat
                }
                return []
            })

        let outcome = await FileMeetingTranscriber.transcribe(
            micURL: micURL,
            systemURL: systemURL,
            meetingID: meeting.id,
            language: "en-US",
            database: db,
            boundary: boundary
        ).outcome

        // The language was given, not probed from speech, so it must not
        // become the next meeting's guess.
        #expect(outcome == .failed(.channels([.mic], localeID: "en-US")))
        #expect(defaults.string(forKey: "lastSpeechLocale") == "fr-FR")
    }

    @Test func autoMeetingWithoutSpeechReportsNoLanguageAndKeepsTheHint() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "T", language: "auto")
        try db.save(meeting)
        // Not decodable as audio: no speech to probe on either channel.
        let micURL = try makeAudioFixture()
        let systemURL = try makeAudioFixture()
        defer {
            try? FileManager.default.removeItem(at: micURL)
            try? FileManager.default.removeItem(at: systemURL)
        }
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "lastSpeechLocale")
        defaults.set("fr-FR", forKey: "lastSpeechLocale")
        defer { restoreLastSpeechLocale(previous) }
        let boundary = FileMeetingTranscriber.Boundary(
            installModel: { _ in }, analyzeChannel: { _ in [] }, isInstalled: { _ in true })

        let result = await FileMeetingTranscriber.transcribe(
            micURL: micURL,
            systemURL: systemURL,
            meetingID: meeting.id,
            language: "auto",
            database: db,
            boundary: boundary)

        let fallback = LanguageDetection.fileProbeLocales(requested: "auto", last: "fr-FR")[0]
        #expect(result.outcome == .completed(localeID: fallback))
        #expect(result.language == nil)
        #expect(defaults.string(forKey: "lastSpeechLocale") == "fr-FR")
    }

    /// An explicitly requested language is the only candidate, so it is
    /// handed back for the meeting row without touching the next-meeting hint.
    @Test func singleCandidateLanguageIsReturnedForTheMeeting() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "T", language: "es-ES")
        try db.save(meeting)
        let missing = URL(fileURLWithPath: "/tmp/granipa-no-such-\(UUID().uuidString).m4a")
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "lastSpeechLocale")
        defaults.set("fr-FR", forKey: "lastSpeechLocale")
        defer { restoreLastSpeechLocale(previous) }
        let boundary = FileMeetingTranscriber.Boundary(
            installModel: { _ in }, analyzeChannel: { _ in [] })

        let result = await FileMeetingTranscriber.transcribe(
            micURL: missing,
            systemURL: missing,
            meetingID: meeting.id,
            language: "es-ES",
            database: db,
            boundary: boundary)

        #expect(result.outcome == .completed(localeID: "es-ES"))
        #expect(result.language == "es-ES")
        #expect(defaults.string(forKey: "lastSpeechLocale") == "fr-FR")
    }

    @Test func modelInstallFailureLeavesLocaleHintUntouched() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "T", language: "en-US")
        try db.save(meeting)
        let missing = URL(fileURLWithPath: "/tmp/granipa-no-such-\(UUID().uuidString).m4a")
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "lastSpeechLocale")
        defaults.set("fr-FR", forKey: "lastSpeechLocale")
        defer { restoreLastSpeechLocale(previous) }
        let boundary = FileMeetingTranscriber.Boundary(
            installModel: { _ in throw TranscriptionError.notAvailable },
            analyzeChannel: { _ in [] })

        let outcome = await FileMeetingTranscriber.transcribe(
            micURL: missing,
            systemURL: missing,
            meetingID: meeting.id,
            language: "en-US",
            database: db,
            boundary: boundary
        ).outcome

        // Installation failed before any audio ran, so the previous hint
        // must survive untouched.
        #expect(outcome == .failed(.modelInstall(localeID: "en-US")))
        #expect(defaults.string(forKey: "lastSpeechLocale") == "fr-FR")
    }

    /// A channel's old segments go only when its replacement succeeded.
    @Test(arguments: [
        // (mic file present, analysis fails) → (mic text, system text)
        (true, true, "old mic", "old system"),
        (false, false, "old mic", "new system"),
        (true, false, "new mic", "new system"),
    ])
    func transcribingAgainReplacesOnlyChannelsThatSucceeded(
        _ micPresent: Bool, _ analysisFails: Bool, _ mic: String, _ system: String
    ) async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "T", language: "en-US")
        try db.save(meeting)
        for (channel, text) in [(AudioChannel.mic, "old mic"), (.system, "old system")] {
            try db.save(
                TranscriptSegment.new(
                    meetingID: meeting.id, channel: channel, speaker: "S", text: text,
                    startSeconds: 0, endSeconds: 1, isFinal: true))
        }
        let micURL = try makeAudioFixture()
        let systemURL = try makeAudioFixture()
        defer {
            try? FileManager.default.removeItem(at: micURL)
            try? FileManager.default.removeItem(at: systemURL)
        }
        if !micPresent { try FileManager.default.removeItem(at: micURL) }
        let boundary = FileMeetingTranscriber.Boundary(
            installModel: { _ in },
            analyzeChannel: { analysis in
                if analysisFails { throw TranscriptionError.noAudioFormat }
                return [
                    TranscriptSegment.new(
                        meetingID: analysis.meetingID, channel: analysis.channel, speaker: "S",
                        text: "new \(analysis.channel == .mic ? "mic" : "system")",
                        startSeconds: 0, endSeconds: 1, isFinal: true)
                ]
            })

        _ = await FileMeetingTranscriber.transcribe(
            micURL: micURL, systemURL: systemURL, meetingID: meeting.id,
            language: "en-US", database: db, boundary: boundary)

        let segments = try db.fetchSegments(meetingID: meeting.id)
        #expect(segments.filter { $0.channel == .mic }.map(\.text) == [mic])
        #expect(segments.filter { $0.channel == .system }.map(\.text) == [system])
    }

    /// Puts `lastSpeechLocale` back exactly as the test found it — including
    /// the "key absent" case.
    private func restoreLastSpeechLocale(_ previous: Any?) {
        if let previous {
            UserDefaults.standard.set(previous, forKey: "lastSpeechLocale")
        } else {
            UserDefaults.standard.removeObject(forKey: "lastSpeechLocale")
        }
    }

    private func makeAudioFixture(byteCount: Int = 4_096) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("granipa-fixture-\(UUID().uuidString).m4a")
        try Data(repeating: 0, count: byteCount).write(to: url)
        return url
    }
}
