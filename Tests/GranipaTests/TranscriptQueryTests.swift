import Foundation
import Testing

@testable import Granipa

@Suite struct TranscriptQueryTests {
    private func seg(
        _ speaker: String,
        _ text: String,
        _ start: Double,
        _ end: Double,
        channel: AudioChannel = .system
    ) -> TranscriptSegment {
        TranscriptSegment.new(
            meetingID: "m", channel: channel, speaker: speaker,
            text: text, startSeconds: start, endSeconds: end, isFinal: true)
    }

    @Test func emptyQueryKeepsOrderAndSpeakerFilter() {
        let rows = [
            seg("Me", "hello there", 0, 1, channel: .mic),
            seg("Speaker 1", "budget review", 1, 2),
            seg("Me", "okay", 2, 3, channel: .mic),
        ]
        let all = TranscriptQuery.filter(segments: rows, query: "  ", speaker: nil)
        #expect(all.map(\.text) == ["hello there", "budget review", "okay"])

        let mine = TranscriptQuery.filter(segments: rows, query: "", speaker: "Me")
        #expect(mine.map(\.text) == ["hello there", "okay"])
    }

    @Test func searchIsCaseInsensitiveAndTreatsWildcardsAsLiterals() {
        let rows = [
            seg("Speaker 1", "Ship the 100% plan", 0, 1),
            seg("Speaker 2", "underscore_token", 1, 2),
            seg("Me", "unrelated", 2, 3, channel: .mic),
        ]
        #expect(
            TranscriptQuery.filter(segments: rows, query: "SHIP", speaker: nil).map(\.text)
                == ["Ship the 100% plan"])
        #expect(
            TranscriptQuery.filter(segments: rows, query: "100%", speaker: nil).map(\.text)
                == ["Ship the 100% plan"])
        #expect(
            TranscriptQuery.filter(segments: rows, query: "underscore_token", speaker: nil)
                .map(\.text) == ["underscore_token"])
        // `%` is a literal character, not a SQL LIKE wildcard, so "%plan" does
        // not match "100% plan" (space between % and plan).
        #expect(TranscriptQuery.filter(segments: rows, query: "%plan", speaker: nil).isEmpty)
        #expect(TranscriptQuery.filter(segments: rows, query: "nope", speaker: nil).isEmpty)
    }

    @Test func searchMatchesSpeakerNameAndIntersectsFilter() {
        let rows = [
            seg("María", "hello", 0, 1),
            seg("Speaker 2", "hello", 1, 2),
        ]
        #expect(
            TranscriptQuery.filter(segments: rows, query: "maría", speaker: nil).map(\.speaker)
                == ["María"])
        #expect(
            TranscriptQuery.filter(segments: rows, query: "hello", speaker: "Speaker 2").map(
                \.speaker) == ["Speaker 2"])
        #expect(
            TranscriptQuery.filter(segments: rows, query: "hello", speaker: "Nobody").isEmpty)
    }

    @Test func speakersPreserveFirstSeenOrder() {
        let rows = [
            seg("Me", "a", 0, 1, channel: .mic),
            seg("Speaker 1", "b", 1, 2),
            seg("Me", "c", 2, 3, channel: .mic),
            seg("Speaker 2", "d", 3, 4),
            seg("Speaker 1", "e", 4, 5),
        ]
        #expect(TranscriptQuery.speakers(in: rows) == ["Me", "Speaker 1", "Speaker 2"])
        #expect(TranscriptQuery.speakers(in: []).isEmpty)
    }

    @Test func containingUsesHalfOpenIntervalsAndKeepsEOF() {
        let rows = [
            seg("Me", "one", 0, 2, channel: .mic),
            seg("Speaker 1", "two", 2, 4),
            seg("Speaker 2", "three", 4, 6),
        ]
        #expect(TranscriptQuery.containing(rows, at: 0).map(\.text) == ["one"])
        #expect(TranscriptQuery.containing(rows, at: 1.9).map(\.text) == ["one"])
        #expect(TranscriptQuery.containing(rows, at: 2).map(\.text) == ["two"])
        #expect(TranscriptQuery.containing(rows, at: 6).map(\.text) == ["three"])
        #expect(TranscriptQuery.containing(rows, at: -1).isEmpty)
        #expect(TranscriptQuery.containing(rows, at: 10).isEmpty)
        #expect(TranscriptQuery.containing(rows, at: .nan).isEmpty)
    }

    @Test func containingReportsOverlappingSpeakersTogether() {
        let rows = [
            seg("Me", "mine", 0, 5, channel: .mic),
            seg("Speaker 1", "theirs", 2, 6),
        ]
        #expect(
            TranscriptQuery.containing(rows, at: 3).map(\.speaker) == ["Me", "Speaker 1"])
        #expect(TranscriptQuery.containing(rows, at: 0).map(\.speaker) == ["Me"])
        #expect(TranscriptQuery.containing(rows, at: 5).map(\.speaker) == ["Speaker 1"])
    }

    @Test func invertedTimesStillContainTheInterval() {
        let rows = [seg("Me", "backwards", 4, 2, channel: .mic)]
        #expect(TranscriptQuery.containing(rows, at: 3).map(\.text) == ["backwards"])
        #expect(TranscriptQuery.containing(rows, at: 4).map(\.text) == ["backwards"])
    }
}

@Suite struct SpeakerTalkTimeTests {
    private func seg(
        _ speaker: String,
        _ start: Double,
        _ end: Double,
        channel: AudioChannel = .system
    ) -> TranscriptSegment {
        TranscriptSegment.new(
            meetingID: "m", channel: channel, speaker: speaker,
            text: speaker, startSeconds: start, endSeconds: end, isFinal: true)
    }

    @Test func emptyAndZeroDurationAreOmitted() {
        #expect(SpeakerTalkTime.report(segments: []).rows.isEmpty)
        let zeros = [
            seg("Me", 1, 1, channel: .mic),
            seg("Speaker 1", 2, 2),
        ]
        let report = SpeakerTalkTime.report(segments: zeros)
        #expect(report.rows.isEmpty)
        #expect(report.summedSeconds == 0)
        #expect(!report.hasOverlap)
    }

    @Test func sequentialSpeakersShareSummedTalkTime() {
        let report = SpeakerTalkTime.report(segments: [
            seg("Me", 0, 10, channel: .mic),
            seg("Speaker 1", 10, 20),
        ])
        #expect(report.rows.map(\.speaker) == ["Me", "Speaker 1"])
        #expect(report.rows.map(\.seconds) == [10, 10])
        #expect(report.rows.map(\.share) == [0.5, 0.5])
        #expect(report.summedSeconds == 20)
        #expect(report.unionSeconds == 20)
        #expect(!report.hasOverlap)
    }

    @Test func overlappingSpeakersKeepBothDurationsAndFlagOverlap() {
        // Me 0–10 and Speaker 1 5–15: 10s each, union 15s.
        let report = SpeakerTalkTime.report(segments: [
            seg("Me", 0, 10, channel: .mic),
            seg("Speaker 1", 5, 15),
        ])
        #expect(report.hasOverlap)
        #expect(report.summedSeconds == 20)
        #expect(report.unionSeconds == 15)
        #expect(report.rows.map(\.speaker) == ["Me", "Speaker 1"])
        #expect(report.rows.map(\.seconds) == [10, 10])
        #expect(report.rows.map(\.share) == [0.5, 0.5])
    }

    @Test func sameSpeakerIntervalsMergeInsteadOfDoubleCounting() {
        let report = SpeakerTalkTime.report(segments: [
            seg("Speaker 1", 0, 5),
            seg("Speaker 1", 4, 8),
        ])
        #expect(report.rows.count == 1)
        #expect(report.rows[0].seconds == 8)
        #expect(report.rows[0].share == 1)
        #expect(!report.hasOverlap)
        #expect(report.unionSeconds == 8)
    }

    @Test func meSortsFirstThenLongestTalkThenName() {
        let report = SpeakerTalkTime.report(segments: [
            seg("Zoe", 0, 3),
            seg("Alex", 3, 10),
            seg("Me", 10, 12, channel: .mic),
        ])
        #expect(report.rows.map(\.speaker) == ["Me", "Alex", "Zoe"])
    }

    @Test func nonFiniteAndInvertedIntervalsAreBounded() {
        var nan = seg("Bad", 0, 4)
        nan.startSeconds = .nan
        let inverted = seg("Speaker 1", 8, 3)
        let report = SpeakerTalkTime.report(segments: [nan, inverted, seg("Me", 0, 4, channel: .mic)])
        #expect(report.rows.map(\.speaker) == ["Me", "Speaker 1"])
        #expect(report.rows[0].seconds == 4)
        #expect(report.rows[1].seconds == 5)
    }
}
