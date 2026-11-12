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
            host: .init(update: { try? db.save($0) }, folder: { _ in nil }, reportError: { _ in }))
        let events = Events()
        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        func drain(_ name: String, waits: Bool) -> MeetingProcessor.Source {
            .live {
                events.log.append("\(name) start")
                if waits { for await _ in gate {} }
                events.log.append("\(name) end")
                return false
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
            host: .init(update: { try? db.save($0) }, folder: { _ in nil }, reportError: { _ in }))
        #expect(await processor.enhance(meetingID: meeting.id) == .nothingToEnhance)

        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        let job = Task {
            await processor.process(meetingID: meeting.id, source: .live {
                for await _ in gate {}
                return false
            })
        }
        while processor.processingMeetingID != meeting.id { await Task.yield() }
        // The pipeline enhances after diarization; an early request must not race it.
        #expect(await processor.enhance(meetingID: meeting.id) == .alreadyRunning)
        release.finish()
        await job.value
    }

    @Test(arguments: [
        (FileMeetingTranscriber.Outcome?.some(.failed(.modelInstall(localeID: "en-US"))),
         MeetingProcessor.EnhanceOutcome.ran, "Transcription failed"),
        (.completed(localeID: "en-US"), .ran, "Notes ready"),
        (nil, .ran, "Notes ready"),
        (.completed(localeID: "en-US"), .failed("CLI missing"), "Notes not written"),
        (.completed(localeID: "en-US"), .nothingToEnhance, "Recording processed"),
    ])
    func completionNoticeNamesTheOutcome(
        _ transcription: FileMeetingTranscriber.Outcome?,
        _ enhancement: MeetingProcessor.EnhanceOutcome,
        _ expectedTitle: String
    ) {
        let notice = MeetingProcessor.completionNotice(
            title: "Standup", transcription: transcription, enhancement: enhancement)
        #expect(notice.title == expectedTitle)
        #expect(notice.body.hasPrefix("Standup"))
        if case .failed(let message) = enhancement {
            #expect(notice.body.contains(message))
        }
    }
}
