import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct EchoBleedFilterTests {
    private func segment(
        _ channel: AudioChannel, _ text: String, _ start: Double, _ end: Double
    ) -> TranscriptSegment {
        TranscriptSegment.new(
            meetingID: "m", channel: channel, speaker: channel == .mic ? "Me" : "Them",
            text: text, startSeconds: start, endSeconds: end, isFinal: true)
    }

    @Test func removesSpeakerBleedAndKeepsTheUsersWords() {
        let mic = [segment(.mic, "Hola, hola. ¿Qué tal? ¿Cómo estás tú?", 0, 4)]
        let system = [segment(.system, "Qué tal, cómo estás tú", 1, 4)]
        let cleaned = EchoBleedFilter.clean(mic: mic, system: system)
        #expect(cleaned.map(\.text) == ["Hola, hola."])
    }

    @Test func dropsASegmentThatIsOnlyBleed() {
        let mic = [segment(.mic, "te comparto pantalla ahora mismo", 10, 13)]
        let system = [segment(.system, "Vale, te comparto pantalla ahora mismo.", 9.5, 13)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system).isEmpty)
    }

    @Test func sameWordsAtAnotherTimeAreNotBleed() {
        let mic = [segment(.mic, "te comparto pantalla ahora mismo", 10, 13)]
        let system = [segment(.system, "te comparto pantalla ahora mismo", 60, 63)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system) == mic)
    }

    @Test func shortCoincidencesStay() {
        let mic = [segment(.mic, "Sí, vale.", 5, 6)]
        let system = [segment(.system, "sí vale", 5, 6)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system) == mic)
    }

    @Test func misheardWordsBetweenBleedRunsGoToo() {
        let mic = [segment(.mic, "uno dos tres cuatro equis cinco seis siete", 0, 5)]
        let system = [segment(.system, "uno dos tres cuatro ye cinco seis siete", 0, 5)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system).isEmpty)
    }

    @Test func applyRewritesOnlyTheMicChannelInTheDatabase() throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "Bleed", language: "es-ES")
        try db.save(meeting)
        let mine = TranscriptSegment.new(
            meetingID: meeting.id, channel: .mic, speaker: "Me",
            text: "Hola, hola. ¿Qué tal? ¿Cómo estás tú?", startSeconds: 0, endSeconds: 4,
            isFinal: true)
        let theirs = TranscriptSegment.new(
            meetingID: meeting.id, channel: .system, speaker: "Them",
            text: "Qué tal, cómo estás tú", startSeconds: 1, endSeconds: 4, isFinal: true)
        try db.save(mine)
        try db.save(theirs)

        try EchoBleedFilter.apply(meetingID: meeting.id, database: db)

        let after = try db.fetchSegments(meetingID: meeting.id)
        #expect(after.filter { $0.channel == .mic }.map(\.text) == ["Hola, hola."])
        #expect(after.filter { $0.channel == .system } == [theirs])
    }

    @Test func postProcessCleansBleedBeforeDiarizationAndNotes() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Granipa/AppState.swift"),
            encoding: .utf8)
        let body = try #require(source.range(of: "func postProcess(")).upperBound
        let rest = source[body...]
        let filter = try #require(rest.range(of: "EchoBleedFilter.apply("))
        let diarize = try #require(rest.range(of: "DiarizationService.diarize("))
        let notes = try #require(rest.range(of: "await enhance(meetingID: meetingID)"))
        #expect(filter.lowerBound < diarize.lowerBound)
        #expect(filter.lowerBound < notes.lowerBound)
    }
}
