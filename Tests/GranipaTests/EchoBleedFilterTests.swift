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
        let cleaned = EchoBleedFilter.clean(mic: mic, system: system, allowCoarseTiming: true)
        #expect(cleaned.map(\.text) == ["Hola, hola."])
        // Bounds follow the kept words: 2 of 7 interpolated tokens over 0–4 s.
        #expect(cleaned.first?.startSeconds == 0)
        #expect(abs((cleaned.first?.endSeconds ?? 0) - 8.0 / 7.0) < 0.001)
    }

    @Test func theOtherSideRepeatingTheUserLaterIsNotBleed() {
        let mic = [segment(.mic, "we should go now", 3, 5)]
        let system = [segment(.system, "we should go now", 5.5, 7.5)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system, allowCoarseTiming: true) == mic)
    }

    @Test func anImmediateRepeatByTheOtherSideIsNotBleed() {
        // Back to back: the user at 3–5 s, the other side echoing the words at 5–7 s.
        let mic = [segment(.mic, "vale perfecto lo cerramos", 3, 5)]
        let system = [segment(.system, "vale perfecto lo cerramos", 5, 7)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system, allowCoarseTiming: true) == mic)
    }

    @Test func deletingAMeetingRemovesItsTranscriptBackup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bleed-delete-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appendingPathComponent(
            EchoBleedFilter.backupFileName(meetingID: "gone", date: Date(timeIntervalSince1970: 1)))
        let second = directory.appendingPathComponent(
            EchoBleedFilter.backupFileName(meetingID: "gone", date: Date(timeIntervalSince1970: 2)))
        let other = directory.appendingPathComponent(
            EchoBleedFilter.backupFileName(meetingID: "kept"))
        for url in [first, second, other] { try Data("[]".utf8).write(to: url) }

        try EchoBleedFilter.removeBackups(meetingID: "gone", from: directory)

        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
        let app = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/Granipa/AppState.swift"),
            encoding: .utf8)
        let body = try #require(app.range(of: "func deleteMeeting(id: String)")).upperBound
        let rest = app[body...]
        let backups = try #require(rest.range(of: "try EchoBleedFilter.removeBackups("))
        let row = try #require(rest.range(of: "try db.deleteMeeting(id: id)"))
        // Backups go first: if they cannot be removed, the meeting stays.
        #expect(backups.lowerBound < row.lowerBound)
    }

    private func timedSegment(
        _ channel: AudioChannel, _ words: [(String, Double)], wordSeconds: Double = 0.3
    ) -> TranscriptSegment {
        let timed = words.map { TranscriptWord(text: $0.0, start: $0.1, end: $0.1 + wordSeconds) }
        return TranscriptSegment.new(
            meetingID: "m", channel: channel, speaker: channel == .mic ? "Me" : "Them",
            text: timed.map(\.text).joined(separator: " "),
            startSeconds: timed.first?.start ?? 0, endSeconds: timed.last?.end ?? 0,
            isFinal: true, words: timed)
    }

    @Test func automaticCleanupLeavesCoarseTimedSegmentsAlone() {
        let mic = [segment(.mic, "te comparto pantalla ahora mismo", 10, 13)]
        let system = [segment(.system, "Vale, te comparto pantalla ahora mismo.", 9.5, 13)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system) == mic)
    }

    @Test func overlappingRecordingPassesAreNotFiltered() {
        // A second recording pass restarts at 0 s: its mic rows overlap the first's.
        let mic = [
            timedSegment(
                .mic,
                [("primera", 0.0), ("grabación", 0.8), ("de", 1.6), ("esta", 2.4), ("reunión", 3.2)]),
            timedSegment(.mic, [("lo", 0.15), ("enviamos", 0.45), ("el", 0.75), ("lunes", 1.05)]),
        ]
        let system = [timedSegment(.system, [("lo", 0.0), ("enviamos", 0.3), ("el", 0.6), ("lunes", 0.9)])]
        #expect(EchoBleedFilter.clean(mic: mic, system: system) == mic)
    }

    @Test func wordTimedEchoIsRemoved() {
        // Speaker bleed: each system word reappears in the mic ~0.15 s later.
        let system = [timedSegment(.system, [("lo", 1.0), ("enviamos", 1.3), ("el", 1.6), ("lunes", 1.9)])]
        let mic = [timedSegment(.mic, [("vale", 0.2), ("lo", 1.15), ("enviamos", 1.45), ("el", 1.75), ("lunes", 2.05)])]
        let cleaned = EchoBleedFilter.clean(mic: mic, system: system)
        #expect(cleaned.map(\.text) == ["vale"])
        #expect(cleaned.first?.words?.map(\.text) == ["vale"])
    }

    @Test func wordTimedReadBackAfterTheOtherTurnStays() {
        // The user repeats the other side's line right after it ends: a turn
        // later, not an echo — even though the meeting is mostly bleed.
        let system = [
            timedSegment(.system, [("lo", 0.0), ("enviamos", 0.3), ("el", 0.6), ("lunes", 0.9)]),
            timedSegment(.system, [("y", 5.0), ("el", 5.3), ("contrato", 5.6), ("también", 5.9)]),
        ]
        let mic = [
            timedSegment(.mic, [("lo", 1.4), ("enviamos", 1.7), ("el", 2.0), ("lunes", 2.3)]),
            timedSegment(.mic, [("y", 5.1), ("el", 5.4), ("contrato", 5.7), ("también", 6.0)]),
        ]
        let cleaned = EchoBleedFilter.clean(mic: mic, system: system)
        #expect(cleaned.map(\.text) == ["lo enviamos el lunes"])
    }

    @Test func userWordsOnBothSidesOfBleedBecomeTwoTimedSegments() {
        let mic = [segment(.mic, "primero yo uno dos tres cuatro luego yo", 0, 8)]
        let system = [segment(.system, "uno dos tres cuatro", 2, 6)]
        let cleaned = EchoBleedFilter.clean(mic: mic, system: system, allowCoarseTiming: true)
        #expect(cleaned.map(\.text) == ["primero yo", "luego yo"])
        #expect(cleaned.map(\.startSeconds) == [0, 6])
        #expect(cleaned.map(\.endSeconds) == [2, 8])
        #expect(cleaned.first?.id == mic.first?.id)
        #expect(Set(cleaned.map(\.id)).count == 2)
    }

    @Test func dropsASegmentThatIsOnlyBleed() {
        let mic = [segment(.mic, "te comparto pantalla ahora mismo", 10, 13)]
        let system = [segment(.system, "Vale, te comparto pantalla ahora mismo.", 9.5, 13)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system, allowCoarseTiming: true).isEmpty)
    }

    @Test func sameWordsAtAnotherTimeAreNotBleed() {
        let mic = [segment(.mic, "te comparto pantalla ahora mismo", 10, 13)]
        let system = [segment(.system, "te comparto pantalla ahora mismo", 60, 63)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system, allowCoarseTiming: true) == mic)
    }

    @Test func shortCoincidencesStay() {
        let mic = [segment(.mic, "Sí, vale.", 5, 6)]
        let system = [segment(.system, "sí vale", 5, 6)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system, allowCoarseTiming: true) == mic)
    }

    @Test func misheardWordsBetweenBleedRunsGoToo() {
        let mic = [segment(.mic, "uno dos tres cuatro equis cinco seis siete", 0, 5)]
        let system = [segment(.system, "uno dos tres cuatro ye cinco seis siete", 0, 5)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system, allowCoarseTiming: true).isEmpty)
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
        #expect(EchoBleedFilter.clean(mic: mic, system: system, allowCoarseTiming: true) == mic)
    }

    @Test func wordsFarApartInsideALongSystemSegmentAreNotBleed() {
        let mic = [segment(.mic, "revisamos los números del trimestre", 2, 5)]
        let long = Array(repeating: "bla", count: 50).joined(separator: " ")
            + " revisamos los números del trimestre"
        let system = [segment(.system, long, 0, 60)]
        #expect(EchoBleedFilter.clean(mic: mic, system: system, allowCoarseTiming: true) == mic)
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

        try EchoBleedFilter.apply(
            meetingID: meeting.id, database: db, backupDirectory: directory, allowCoarseTiming: true)

        let after = try db.fetchSegments(meetingID: meeting.id)
        #expect(after.filter { $0.channel == .mic }.map(\.text) == ["Hola, hola."])
        #expect(after.filter { $0.channel == .system } == [theirs])
        let backups = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(backups.count == 1)
        let backup = try Data(contentsOf: directory.appendingPathComponent(try #require(backups.first)))
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
        let filter = try #require(rest.range(of: "cleanSpeakerBleed(meetingID: meetingID)"))
        let diarize = try #require(rest.range(of: "DiarizationService.diarize("))
        let notes = try #require(rest.range(of: "await enhance(meetingID: meetingID)"))
        #expect(filter.lowerBound < diarize.lowerBound)
        #expect(filter.lowerBound < notes.lowerBound)
    }

    @Test func notesButtonsCleanBleedBeforeRegenerating() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let app = try String(
            contentsOf: root.appendingPathComponent("Sources/Granipa/AppState.swift"),
            encoding: .utf8)
        let body = try #require(app.range(of: "func regenerateNotes(")).upperBound
        let rest = app[body...]
        let clean = try #require(rest.range(of: "cleanSpeakerBleed(meetingID: meetingID)"))
        let notes = try #require(rest.range(of: "await enhance(meetingID: meetingID)"))
        #expect(clean.lowerBound < notes.lowerBound)
        for view in ["MeetingRecordedViews.swift", "EnhancedNotesView.swift"] {
            let source = try String(
                contentsOf: root.appendingPathComponent("Sources/Granipa/UI/\(view)"),
                encoding: .utf8)
            #expect(source.contains("app.regenerateNotes(meetingID:"))
            #expect(!source.contains("app.enhance(meetingID:"))
        }
    }
}
