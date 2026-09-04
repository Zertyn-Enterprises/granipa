import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct DictationHistoryTests {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    @Test func wordCountSplitsOnWhitespace() {
        #expect(DictationStats.wordCount(in: "") == 0)
        #expect(DictationStats.wordCount(in: "  hola  mundo\n") == 2)
        #expect(DictationStats.wordCount(in: "one") == 1)
    }

    @Test func timeSavedIsTypingAtFortyWPM() {
        let stats = DictationStats(words: 6_906, durationSeconds: 60, apps: 6)
        #expect(abs(stats.timeSavedSeconds - (6_906 / 40 * 60)) < 0.01)
        #expect(stats.savedLabel() == "2.9 hours")
        #expect(stats.averageWPM == 6906)
    }

    @Test func insertFetchSearchAndStats() throws {
        let db = try makeDatabase()
        let first = DictationEntry.new(
            text: "hello world", durationSeconds: 2, sourceApp: "Safari")
        var second = DictationEntry.new(
            text: "otra nota", durationSeconds: 4, sourceApp: "Mail")
        second.createdAt = Date.now.addingTimeInterval(-8_000)
        try db.insertDictationEntry(first)
        try db.insertDictationEntry(second)

        let all = try db.fetchDictationEntries()
        #expect(all.count == 2)

        let search = try db.fetchDictationEntries(search: "HELLO")
        #expect(search.count == 1)
        #expect(search[0].text == "hello world")
        #expect(search[0].wordCount == 2)

        let stats = try db.dictationStats()
        #expect(stats.words == 4)
        #expect(stats.apps == 2)
        #expect(abs(stats.durationSeconds - 6) < 0.001)

        try db.deleteDictationEntry(id: first.id)
        #expect(try db.fetchDictationEntries().count == 1)
    }

    @Test func statsSinceFiltersOldEntries() throws {
        let db = try makeDatabase()
        var old = DictationEntry.new(text: "ayer", durationSeconds: 10, sourceApp: "X")
        old.createdAt = Date.now.addingTimeInterval(-86_400 * 3)
        try db.insertDictationEntry(old)
        try db.insertDictationEntry(
            DictationEntry.new(text: "hoy dos", durationSeconds: 5, sourceApp: "Y"))

        let recent = try db.dictationStats(since: Calendar.current.startOfDay(for: .now))
        #expect(recent.words == 2)
        #expect(recent.apps == 1)
    }
}
