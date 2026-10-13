import CoreMedia
import Foundation
import GRDB
import Speech
import Testing

@testable import Granipa

@Suite struct TranscriptWordsTests {
    private func timed(_ word: String, _ start: Double, _ end: Double) -> AttributedString {
        var text = AttributedString(word)
        text.audioTimeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600))
        return text
    }

    @Test func runsWithTimeRangesBecomeWords() {
        var text = timed("hola ", 1.0, 1.4)
        text.append(timed("mundo", 1.5, 2.0))
        #expect(
            TranscriptWords.from(text) == [
                TranscriptWord(text: "hola", start: 1.0, end: 1.4),
                TranscriptWord(text: "mundo", start: 1.5, end: 2.0),
            ])
        #expect(TranscriptWords.from(AttributedString("sin tiempos")) == nil)
    }

    @Test func partiallyTaggedTextHasNoWordTimings() {
        var text = timed("hola ", 1.0, 1.4)
        text.append(AttributedString("mundo"))
        #expect(TranscriptWords.from(text) == nil)
    }

    @Test func wordTimingsPersistAndOldRowsReadAsNil() throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "Words", language: "es-ES")
        try db.save(meeting)
        let words = [TranscriptWord(text: "hola", start: 1, end: 1.4)]
        let timedSegment = TranscriptSegment.new(
            meetingID: meeting.id, channel: .mic, speaker: "Me", text: "hola",
            startSeconds: 1, endSeconds: 1.4, isFinal: true, words: words)
        let legacy = TranscriptSegment.new(
            meetingID: meeting.id, channel: .system, speaker: "Them", text: "adiós",
            startSeconds: 2, endSeconds: 3, isFinal: true)
        try db.save(timedSegment)
        try db.save(legacy)

        let stored = try db.fetchSegments(meetingID: meeting.id)
        #expect(stored.first?.words == words)
        #expect(stored.last?.words == nil)
    }
}
