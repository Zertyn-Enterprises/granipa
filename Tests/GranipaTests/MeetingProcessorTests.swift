import Foundation
import GRDB
import Testing

@testable import Granipa

@MainActor
@Suite struct MeetingProcessorTests {
    @MainActor final class Events {
        var log: [String] = []
    }

    @Test func jobsRunOneAtATimeAndAQueuedJobCanBeDropped() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        var meetings: [Meeting] = []
        for title in ["A", "B", "C"] {
            var meeting = Meeting.new(title: title, language: "en-US")
            meeting.status = .processing
            try db.save(meeting)
            meetings.append(meeting)
        }
        let processor = MeetingProcessor(
            database: db,
            host: .init(update: { try? db.save($0) }, folder: { _ in nil }, reportError: { _ in }),
            transcriptBackups: { _ in nil })
        let events = Events()
        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        func drain(_ name: String, waits: Bool) -> MeetingProcessor.Source {
            .live {
                events.log.append("\(name) start")
                if waits { for await _ in gate {} }
                events.log.append("\(name) end")
                return .init(usedMuseForSystem: false)
            }
        }

        let first = Task { await processor.process(meetingID: meetings[0].id, source: drain("A", waits: true)) }
        while processor.processingMeetingID != meetings[0].id { await Task.yield() }
        let second = Task { await processor.process(meetingID: meetings[1].id, source: drain("B", waits: false)) }
        let third = Task { await processor.process(meetingID: meetings[2].id, source: drain("C", waits: false)) }
        for _ in 0..<20 { await Task.yield() }

        #expect(!processor.cancelQueued(meetingID: meetings[0].id))
        #expect(processor.cancelQueued(meetingID: meetings[2].id))
        release.finish()
        await first.value
        await second.value
        await third.value

        #expect(events.log == ["A start", "A end", "B start", "B end"])
        #expect(try db.fetchMeeting(id: meetings[1].id)?.status == .ready)
        #expect(try db.fetchMeeting(id: meetings[2].id)?.status == .processing)
    }

    @Test func enhanceSaysWhyNothingRan() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "Empty", language: "en-US")
        try db.save(meeting)
        let processor = MeetingProcessor(
            database: db,
            host: .init(update: { try? db.save($0) }, folder: { _ in nil }, reportError: { _ in }),
            transcriptBackups: { _ in nil })
        #expect(await processor.enhance(meetingID: meeting.id) == .nothingToEnhance)

        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        let job = Task {
            await processor.process(meetingID: meeting.id, source: .live {
                for await _ in gate {}
                return .init(usedMuseForSystem: false)
            })
        }
        while processor.processingMeetingID != meeting.id { await Task.yield() }
        // The pipeline enhances after diarization; an early request must not race it.
        #expect(await processor.enhance(meetingID: meeting.id) == .alreadyRunning)
        release.finish()
        await job.value
    }

    @Test(arguments: [
        (true, MeetingProcessor.EnhanceOutcome.ran, "Transcription failed"),
        (true, .failed("CLI missing"), "Transcription failed"),
        (false, .ran, "Notes ready"),
        (false, .failed("CLI missing"), "Notes not written"),
        (false, .nothingToEnhance, "Recording processed"),
    ])
    func completionNoticeNamesTheOutcome(
        _ transcriptionFailed: Bool,
        _ enhancement: MeetingProcessor.EnhanceOutcome,
        _ expectedTitle: String
    ) {
        let notice = MeetingProcessor.completionNotice(
            title: "Standup", transcriptionFailed: transcriptionFailed, enhancement: enhancement)
        #expect(notice.title == expectedTitle)
        #expect(notice.body.hasPrefix("Standup"))
        if !transcriptionFailed, case .failed(let message) = enhancement {
            #expect(notice.body.contains(message))
        }
    }

    @Test(arguments: [
        (MeetingStatus.processing, true, false, MeetingReprocessing.LaunchAction.reprocess),
        (.processing, true, true, .markReady),
        (.processing, false, false, .markReady),
        (.recording, true, false, .markReady),
        (.ready, true, true, .keep),
    ])
    func launchRecoveryRerunsAnInterruptedMeetingOnce(
        _ status: MeetingStatus, _ hasAudio: Bool, _ attemptUnfinished: Bool,
        _ expected: MeetingReprocessing.LaunchAction
    ) {
        #expect(
            MeetingReprocessing.launchAction(
                status: status, hasAudio: hasAudio, attemptUnfinished: attemptUnfinished)
                == expected)
    }

    /// The record is what stops a meeting that kills the app from being
    /// re-run at every launch: written before the run, removed after it.
    @Test func recoveryAttemptRecordSurvivesUntilTheRunEnds() throws {
        let suite = "granipa-recovery-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        MeetingReprocessing.recordAttempt(meetingID: "a", unfinished: true, defaults)
        MeetingReprocessing.recordAttempt(meetingID: "b", unfinished: true, defaults)
        #expect(MeetingReprocessing.unfinishedAttempts(defaults) == ["a", "b"])

        MeetingReprocessing.recordAttempt(meetingID: "a", unfinished: false, defaults)
        #expect(MeetingReprocessing.unfinishedAttempts(defaults) == ["b"])

        MeetingReprocessing.forgetAttempts(defaults)
        #expect(MeetingReprocessing.unfinishedAttempts(defaults).isEmpty)
    }

    @Test(arguments: [
        (MeetingStatus.ready, false, false, true, true),
        (.processing, false, false, true, false),
        (.ready, true, false, true, false),
        (.ready, false, true, true, false),
        (.ready, false, false, false, false),
    ])
    func transcribeAgainNeedsAnIdleMeetingWithAudio(
        _ status: MeetingStatus, _ isRecording: Bool, _ isEnhancing: Bool, _ hasAudio: Bool,
        _ expected: Bool
    ) {
        #expect(
            MeetingReprocessing.canTranscribeAgain(
                status: status, isRecording: isRecording, isEnhancing: isEnhancing,
                hasAudio: hasAudio) == expected)
    }
}
