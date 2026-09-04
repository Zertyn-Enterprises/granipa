import AVFoundation
import GRDB
import Testing

@testable import Granipa

@Suite struct TranscriptionCoordinatorTests {
    private func segment(
        _ start: Double, channel: AudioChannel = .mic
    ) -> TranscriptSegment {
        TranscriptSegment.new(
            meetingID: "m1",
            channel: channel,
            speaker: channel == .mic ? "Me" : "Speaker A",
            text: "t\(Int(start))",
            startSeconds: start,
            endSeconds: start + 2,
            isFinal: true)
    }

    @Test func adoptMergeKeepsSystemFinalsOnTheTimeline() {
        // Pre-adopt, liveSegments can only hold Muse system finals; a stray
        // mic segment in `existing` (impossible via apply()) is dropped.
        let micFinals = [segment(0), segment(10)]
        let existing = [segment(5, channel: .system), segment(2)]
        let merged = TranscriptionCoordinator.mergedLiveSegments(
            micFinals: micFinals, existing: existing)
        #expect(merged.map(\.startSeconds) == [0, 5, 10])
        #expect(merged.filter { $0.channel == .system }.count == 1)
    }

    @Test func adoptMergeWithoutSystemFinalsIsMicOnly() {
        let micFinals = [segment(4), segment(1)]
        let merged = TranscriptionCoordinator.mergedLiveSegments(
            micFinals: micFinals, existing: [])
        #expect(merged.map(\.startSeconds) == [1, 4])
        #expect(merged.allSatisfy { $0.channel == .mic })
    }

    @Test func chunkFanDeliversToEverySubscriber() async {
        let fan = ChunkFan()
        let first = fan.subscribe().stream
        let second = fan.subscribe().stream
        fan.yield(chunk(1))
        fan.finish()
        var receivedFirst: [Double] = []
        for await chunk in first { receivedFirst.append(chunk.startSeconds ?? -1) }
        var receivedSecond: [Double] = []
        for await chunk in second { receivedSecond.append(chunk.startSeconds ?? -1) }
        #expect(receivedFirst == [1])
        #expect(receivedSecond == [1])
    }

    @Test func chunkFanFreshSubscriptionAfterFinishStartsEmpty() async {
        let fan = ChunkFan()
        _ = fan.subscribe()
        fan.yield(chunk(1))
        fan.finish()
        // A later attempt's stream must not replay the dead attempt's chunks.
        let late = fan.subscribe().stream
        fan.finish()
        var received: [Double] = []
        for await chunk in late { received.append(chunk.startSeconds ?? -1) }
        #expect(received.isEmpty)
    }

    @Test func chunkFanDropsAbandonedSubscribers() async {
        let fan = ChunkFan()
        let first = fan.subscribe()
        #expect(fan.subscriberCount == 1)
        first.continuation.finish()
        await Task.yield()
        #expect(fan.subscriberCount == 0)
        let second = fan.subscribe()
        fan.yield(chunk(2))
        fan.finish()
        var received: [Double] = []
        for await chunk in second.stream { received.append(chunk.startSeconds ?? -1) }
        #expect(received == [2])
    }

    @Test func volatileMailboxPublishesOnlyWhenDirty() {
        let box = VolatileMailbox()
        #expect(box.snapshotIfDirty() == nil)
        box.set(channel: .mic, text: "hello")
        let first = box.snapshotIfDirty()
        #expect(first?.mic == "hello")
        #expect(first?.system == "")
        #expect(box.snapshotIfDirty() == nil)
        box.set(channel: .system, text: "them")
        let second = box.snapshotIfDirty()
        #expect(second?.mic == "hello")
        #expect(second?.system == "them")
        box.reset()
        #expect(box.snapshotIfDirty() == nil)
        box.set(channel: .mic, text: "again")
        #expect(box.snapshotIfDirty()?.mic == "again")
    }

    @Test func onceFlagRunsActionOnce() {
        final class Counter: @unchecked Sendable {
            var value = 0
        }
        let counter = Counter()
        let once = OnceFlag { counter.value += 1 }
        once.fire()
        once.fire()
        once.fire()
        #expect(counter.value == 1)
    }

    @Test @MainActor func retryRequiresFailedPhase() async throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        var meeting = Meeting.new(title: "T", language: "en-US")
        try db.save(meeting)
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("coordinator-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let session = RecordingSession(meetingID: meeting.id, directory: dir) { _, _ in }
        let coordinator = TranscriptionCoordinator(
            meetingID: meeting.id, language: "en-US", session: session, database: db)

        // Not failed: the retry must be a no-op, not a second pipeline.
        coordinator.retryIfFailed()
        #expect(coordinator.phase == .preparing)
    }

    private func chunk(_ start: Int) -> AudioChunk {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1)!
        buffer.frameLength = 1
        return AudioChunk(buffer: buffer, startSeconds: Double(start))
    }
}
