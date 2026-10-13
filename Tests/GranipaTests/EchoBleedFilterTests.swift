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
        // Bounds follow the kept words: 2 of 7 interpolated tokens over 0–4 s.
        #expect(cleaned.first?.startSeconds == 0)
        #expect(abs((cleaned.first?.endSeconds ?? 0) - 8.0 / 7.0) < 0.001)
    }

    @Test func theOtherSideRepeatingTheUserLaterIsNotBleed() {
        let mic = [segment(.mic, "we should go now", 3, 5)]
        let system = [segment(.system, "we should go now", 5.5, 7.5)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system) == mic)
    }

    @Test func userWordsOnBothSidesOfBleedBecomeTwoTimedSegments() {
        let mic = [segment(.mic, "primero yo uno dos tres cuatro luego yo", 0, 8)]
        let system = [segment(.system, "uno dos tres cuatro", 2, 6)]
        let cleaned = EchoBleedFilter.clean(mic: mic, system: system)
        #expect(cleaned.map(\.text) == ["primero yo", "luego yo"])
        #expect(cleaned.map(\.startSeconds) == [0, 6])
        #expect(cleaned.map(\.endSeconds) == [2, 8])
        #expect(cleaned.first?.id == mic.first?.id)
        #expect(Set(cleaned.map(\.id)).count == 2)
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

    @Test func headphoneMeetingKeepsTheUsersReadBacks() {
        // Mostly the user's own speech; one genuine read-back of the other side.
        let mic = [
            segment(.mic, "Perfecto, yo me encargo de revisar el contrato esta tarde", 0, 4),
            segment(.mic, "y luego te paso las notas con los cambios que veamos", 5, 9),
            segment(.mic, "vale entonces enviamos el lunes", 20, 22),
            segment(.mic, "también quiero hablar del presupuesto del proyecto nuevo", 30, 34),
        ]
        let system = [segment(.system, "entonces enviamos el lunes", 18, 20)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system) == mic)
    }

    @Test func wordsFarApartInsideALongSystemSegmentAreNotBleed() {
        let mic = [segment(.mic, "revisamos los números del trimestre", 2, 5)]
        let long = Array(repeating: "bla", count: 50).joined(separator: " ")
            + " revisamos los números del trimestre"
        let system = [segment(.system, long, 0, 60)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system) == mic)
    }

    @Test func applyBacksUpTheOriginalAndRewritesOnlyTheMicChannel() throws {
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
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bleed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try EchoBleedFilter.apply(meetingID: meeting.id, database: db, backupDirectory: directory)

        let after = try db.fetchSegments(meetingID: meeting.id)
        #expect(after.filter { $0.channel == .mic }.map(\.text) == ["Hola, hola."])
        #expect(after.filter { $0.channel == .system } == [theirs])
        let backup = try Data(
            contentsOf: directory.appendingPathComponent(
                EchoBleedFilter.backupFileName(meetingID: meeting.id)))
        #expect(try JSONDecoder().decode([TranscriptSegment].self, from: backup) == [mine])
    }

    @Test func applyWithoutABackupLocationChangesNothing() throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        let meeting = Meeting.new(title: "Bleed", language: "es-ES")
        try db.save(meeting)
        let mine = TranscriptSegment.new(
            meetingID: meeting.id, channel: .mic, speaker: "Me",
            text: "te comparto pantalla ahora mismo", startSeconds: 0, endSeconds: 3,
            isFinal: true)
        try db.save(mine)
        try db.save(
            TranscriptSegment.new(
                meetingID: meeting.id, channel: .system, speaker: "Them",
                text: "te comparto pantalla ahora mismo", startSeconds: 0, endSeconds: 3,
                isFinal: true))

        try EchoBleedFilter.apply(meetingID: meeting.id, database: db, backupDirectory: nil)

        #expect(try db.fetchSegments(meetingID: meeting.id).filter { $0.channel == .mic } == [mine])
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
