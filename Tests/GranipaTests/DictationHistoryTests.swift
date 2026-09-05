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

    private func seed(
        _ db: AppDatabase, text: String, minutesAgo: Double, sourceApp: String?
    ) throws {
        var entry = DictationEntry.new(text: text, durationSeconds: 1, sourceApp: sourceApp)
        entry.createdAt = Date.now.addingTimeInterval(-minutesAgo * 60)
        try db.insertDictationEntry(entry)
    }

    @Test func pagingUsesOffsetAndKeepsNewestFirst() throws {
        let db = try makeDatabase()
        for index in 0..<7 {
            try seed(db, text: "entry \(index)", minutesAgo: Double(index), sourceApp: nil)
        }

        let firstPage = try db.fetchDictationEntries(limit: 5)
        let secondPage = try db.fetchDictationEntries(limit: 5, offset: 5)
        #expect(firstPage.map(\.text) == (0..<5).map { "entry \($0)" })
        #expect(secondPage.map(\.text) == ["entry 5", "entry 6"])
        #expect(try db.dictationEntryCount() == 7)
    }

    @Test func sourceAppFilterComposesWithSearchAndCount() throws {
        let db = try makeDatabase()
        try seed(db, text: "ship the card", minutesAgo: 1, sourceApp: "Safari")
        try seed(db, text: "ship the docs", minutesAgo: 2, sourceApp: "Mail")
        try seed(db, text: "unrelated", minutesAgo: 3, sourceApp: "Safari")
        try seed(db, text: "ship in secret", minutesAgo: 4, sourceApp: nil)

        let safariShips = try db.fetchDictationEntries(search: "ship", sourceApp: "Safari")
        #expect(safariShips.map(\.text) == ["ship the card"])

        #expect(try db.dictationEntryCount(search: "ship") == 3)
        #expect(try db.dictationEntryCount(sourceApp: "Mail") == 1)
        #expect(try db.dictationEntryCount(search: "ship", sourceApp: "Mail") == 1)
        #expect(try db.dictationEntryCount() == 4)
    }

    @Test func sourceAppsListDistinctNonNullWithinWindow() throws {
        let db = try makeDatabase()
        try seed(db, text: "a", minutesAgo: 1, sourceApp: "Safari")
        try seed(db, text: "b", minutesAgo: 2, sourceApp: "Mail")
        try seed(db, text: "c", minutesAgo: 3, sourceApp: "Safari")
        try seed(db, text: "d", minutesAgo: 4, sourceApp: nil)
        try seed(db, text: "old", minutesAgo: 60_000, sourceApp: "TextEdit")

        #expect(try db.dictationSourceApps() == ["Mail", "Safari", "TextEdit"])
        #expect(
            try db.dictationSourceApps(since: Date.now.addingTimeInterval(-3_600)) == [
                "Mail", "Safari",
            ])
    }

    @Test func durationLabelsUseClockFormat() {
        #expect(DictationLibraryFormat.duration(0) == "0:00")
        #expect(DictationLibraryFormat.duration(8.4) == "0:08")
        #expect(DictationLibraryFormat.duration(75) == "1:15")
        #expect(DictationLibraryFormat.duration(3_661) == "1:01:01")
        #expect(DictationLibraryFormat.duration(-5) == "0:00")
    }

    @Test func titleIsFirstLineAndSnippetTheRest() {
        let single = DictationLibraryFormat.titleAndSnippet("ship the card")
        #expect(single.title == "ship the card")
        #expect(single.snippet.isEmpty)

        let multi = DictationLibraryFormat.titleAndSnippet("Quarter notes\nbuy oats\ncall Iris")
        #expect(multi.title == "Quarter notes")
        #expect(multi.snippet == "buy oats\ncall Iris")

        let leading = DictationLibraryFormat.titleAndSnippet("\n  \nhello\nworld")
        #expect(leading.title == "hello")
        #expect(leading.snippet == "world")
    }

    @Test func dayGroupsSortDaysNewestFirst() throws {
        let db = try makeDatabase()
        try seed(db, text: "morning", minutesAgo: 300, sourceApp: nil)
        try seed(db, text: "afternoon", minutesAgo: 30, sourceApp: nil)
        try seed(db, text: "yesterday", minutesAgo: 60 * 30, sourceApp: nil)

        let groups = DictationLibraryFormat.dayGroups(
            from: try db.fetchDictationEntries())
        #expect(groups.count == 2)
        #expect(groups[0].entries.map(\.text) == ["afternoon", "morning"])
        #expect(groups[1].entries.map(\.text) == ["yesterday"])
    }
}
