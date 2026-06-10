import Foundation
import Testing

@testable import Granipa

@Suite struct SpeakerMappingTests {
    private func segment(_ text: String, _ start: Double, _ end: Double) -> TranscriptSegment {
        TranscriptSegment.new(
            meetingID: "m", channel: .system, speaker: "Them",
            text: text, startSeconds: start, endSeconds: end, isFinal: true)
    }

    @Test func relabelsByDominantOverlap() {
        let segments = [segment("hello", 0, 4), segment("world", 5, 9)]
        let spans = [
            SpeakerSpan(speakerID: "1", start: 0, end: 4.5),
            SpeakerSpan(speakerID: "2", start: 4.5, end: 10),
        ]
        let result = SpeakerMapping.relabel(segments: segments, spans: spans)
        #expect(result.map(\.speaker) == ["Speaker 1", "Speaker 2"])
    }

    @Test func keepsThemWhenNoMeaningfulOverlap() {
        let segments = [segment("orphan", 100, 104)]
        let spans = [SpeakerSpan(speakerID: "1", start: 0, end: 10)]
        let result = SpeakerMapping.relabel(segments: segments, spans: spans)
        #expect(result[0].speaker == "Them")
    }

    @Test func mixedOverlapPicksLargestShare() {
        let segments = [segment("split", 0, 10)]
        let spans = [
            SpeakerSpan(speakerID: "1", start: 0, end: 3),
            SpeakerSpan(speakerID: "2", start: 3, end: 10),
        ]
        let result = SpeakerMapping.relabel(segments: segments, spans: spans)
        #expect(result[0].speaker == "Speaker 2")
    }

    @Test func parsesNamesAndFiltersJunk() {
        let raw = """
            Sure! Here you go:
            {"Speaker 1": "Maria", "Speaker 2": null, "Speaker 3": "unknown", "Speaker 4": ""}
            """
        let names = SpeakerMapping.parseNames(
            raw, speakerLabels: ["Speaker 1", "Speaker 2", "Speaker 3", "Speaker 4"])
        #expect(names == ["Speaker 1": "Maria"])
    }

    @Test func appliesNamesOnlyToMatchingLabels() {
        let segments = [segment("hola", 0, 2), segment("adios", 3, 5)]
        var relabeled = SpeakerMapping.relabel(
            segments: segments,
            spans: [
                SpeakerSpan(speakerID: "1", start: 0, end: 2.5),
                SpeakerSpan(speakerID: "2", start: 2.5, end: 5),
            ])
        relabeled = SpeakerMapping.applyNames(["Speaker 1": "Maria"], to: relabeled)
        #expect(relabeled.map(\.speaker) == ["Maria", "Speaker 2"])
    }
}
