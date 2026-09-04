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
            analyzeChannel: { _ in })

        let outcome = await FileMeetingTranscriber.transcribe(
            micURL: missing,
            systemURL: missing,
            meetingID: meeting.id,
            language: "en-US",
            database: db,
            boundary: boundary)

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
            analyzeChannel: { _ in })

        let outcome = await FileMeetingTranscriber.transcribe(
            micURL: missing,
            systemURL: missing,
            meetingID: meeting.id,
            language: "en-US",
            database: db,
            boundary: boundary)

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
                try analysis.database.save(
                    TranscriptSegment.new(
                        meetingID: analysis.meetingID,
                        channel: analysis.channel,
                        speaker: "Them",
                        text: "hello",
                        startSeconds: 0,
                        endSeconds: 1,
                        isFinal: true))
            })

        let outcome = await FileMeetingTranscriber.transcribe(
            micURL: micURL,
            systemURL: systemURL,
            meetingID: meeting.id,
            language: "en-US",
            database: db,
            boundary: boundary)

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
            boundary: boundary)

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
            boundary: boundary)

        #expect(outcome == .failed(.channels([.system], localeID: "en-US")))
        #expect((try db.fetchSegments(meetingID: meeting.id)).isEmpty)
    }

    @Test func partialChannelFailureStillStoresLocaleHint() async throws {
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
        defaults.removeObject(forKey: "lastSpeechLocale")
        defer { restoreLastSpeechLocale(previous) }
        let boundary = FileMeetingTranscriber.Boundary(
            installModel: { _ in },
            analyzeChannel: { analysis in
                if analysis.channel == .mic {
                    throw TranscriptionError.noAudioFormat
                }
            })

        let outcome = await FileMeetingTranscriber.transcribe(
            micURL: micURL,
            systemURL: systemURL,
            meetingID: meeting.id,
            language: "en-US",
            database: db,
            boundary: boundary)

        // The mic channel failed, but the locale was still picked from real
        // audio, so the hint for the next meeting must be stored.
        #expect(outcome == .failed(.channels([.mic], localeID: "en-US")))
        #expect(defaults.string(forKey: "lastSpeechLocale") == "en-US")
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
            analyzeChannel: { _ in })

        let outcome = await FileMeetingTranscriber.transcribe(
            micURL: missing,
            systemURL: missing,
            meetingID: meeting.id,
            language: "en-US",
            database: db,
            boundary: boundary)

        // Installation failed before any audio ran, so the previous hint
        // must survive untouched.
        #expect(outcome == .failed(.modelInstall(localeID: "en-US")))
        #expect(defaults.string(forKey: "lastSpeechLocale") == "fr-FR")
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
