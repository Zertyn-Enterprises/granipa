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

    @Test func librarySnapshotPagesPastNewerInsertsWithoutRepeats() throws {
        let db = try makeDatabase()
        for index in 0..<7 {
            try seed(db, text: "entry \(index)", minutesAgo: Double(index) + 1, sourceApp: nil)
        }

        let page1 = try db.fetchDictationLibrarySnapshot(limit: 5)
        #expect(page1.entries.map(\.text) == (0..<5).map { "entry \($0)" })
        #expect(page1.total == 7)

        // Three dictations are saved while the list is mounted.
        for index in 0..<3 {
            try seed(db, text: "new \(index)", minutesAgo: 0.1 * Double(index + 1), sourceApp: nil)
        }

        let oldest = try #require(page1.entries.last)
        let page2 = try db.fetchDictationLibrarySnapshot(
            limit: 5, before: (createdAt: oldest.createdAt, id: oldest.id))
        let page1IDs = Set(page1.entries.map(\.id))
        #expect(page2.entries.map(\.text) == ["entry 5", "entry 6"])
        #expect(page2.entries.allSatisfy { !page1IDs.contains($0.id) })
        #expect(page2.total == 10)
    }

    @Test func librarySnapshotCursorIgnoresDeletedShownRows() throws {
        let db = try makeDatabase()
        for index in 0..<7 {
            try seed(db, text: "entry \(index)", minutesAgo: Double(index) + 1, sourceApp: nil)
        }

        let page1 = try db.fetchDictationLibrarySnapshot(limit: 5)
        for row in page1.entries.prefix(2) {
            try db.deleteDictationEntry(id: row.id)
        }

        let oldest = try #require(page1.entries.last)
        let page2 = try db.fetchDictationLibrarySnapshot(
            limit: 5, before: (createdAt: oldest.createdAt, id: oldest.id))
        #expect(page2.entries.map(\.text) == ["entry 5", "entry 6"])
        #expect(page2.total == 5)
    }

    @Test func librarySnapshotTiebreaksIdenticalCreatedAtByID() throws {
        let db = try makeDatabase()
        let sameInstant = Date.now.addingTimeInterval(-120)
        for index in 0..<5 {
            var entry = DictationEntry.new(
                text: "tie \(index)", durationSeconds: 1, sourceApp: nil)
            entry.createdAt = sameInstant
            try db.insertDictationEntry(entry)
        }

        var seen = Set<String>()
        var cursor: (createdAt: Date, id: String)?
        var pages = 0
        while seen.count < 5 {
            let page = try db.fetchDictationLibrarySnapshot(limit: 2, before: cursor)
            #expect(!page.entries.isEmpty)
            for pair in zip(page.entries, page.entries.dropFirst()) {
                #expect(pair.0.id > pair.1.id)
            }
            seen.formUnion(page.entries.map(\.id))
            guard let oldest = page.entries.last else { break }
            cursor = (createdAt: oldest.createdAt, id: oldest.id)
            pages += 1
            if pages > 5 { Issue.record("keyset paging did not terminate"); break }
        }
        #expect(seen.count == 5)
        #expect(pages == 3)
    }

    @Test func librarySnapshotCountsAndStatsMatchTheSameRead() throws {
        let db = try makeDatabase()
        try seed(db, text: "a b", minutesAgo: 1, sourceApp: "Safari")
        try seed(db, text: "c", minutesAgo: 2, sourceApp: "Mail")
        try seed(db, text: "d e", minutesAgo: 3, sourceApp: "Safari")

        let snapshot = try db.fetchDictationLibrarySnapshot(limit: 2)
        #expect(snapshot.entries.count == 2)
        #expect(snapshot.total == 3)
        #expect(snapshot.stats.words == 5)
        #expect(snapshot.stats.apps == 2)
        #expect(snapshot.sourceApps == ["Mail", "Safari"])
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

    @Test func pageGateAllowsOnlyTheAppliedQuery() {
        let applied = DictationLibraryQuery(search: "ship", period: .week, sourceApp: "Mail")

        #expect(DictationLibraryQuery.pageQuery(applied: applied, current: applied) != nil)
        #expect(DictationLibraryQuery.pageQuery(applied: nil, current: applied) == nil)
        #expect(DictationLibraryQuery.pageQuery(
            applied: applied,
            current: DictationLibraryQuery(search: "shipped", period: .week, sourceApp: "Mail"))
            == nil)
        #expect(DictationLibraryQuery.pageQuery(
            applied: applied,
            current: DictationLibraryQuery(search: "ship", period: .all, sourceApp: "Mail"))
            == nil)
        #expect(DictationLibraryQuery.pageQuery(
            applied: applied,
            current: DictationLibraryQuery(search: "ship", period: .week, sourceApp: "Safari"))
            == nil)
        #expect(DictationLibraryQuery.pageQuery(
            applied: applied,
            current: DictationLibraryQuery(search: "ship", period: .week, sourceApp: nil))
            == nil)
    }

    @Test func pageGateNormalizesSearchWhitespace() {
        // During the debounce the field can hold " ship " while the applied
        // query trimmed it; both describe the same query, so paging must pass.
        let applied = DictationLibraryQuery(search: "ship", period: .all, sourceApp: nil)
        let typedNow = DictationLibraryQuery(search: " ship ", period: .all, sourceApp: nil)
        #expect(applied == typedNow)
        #expect(DictationLibraryQuery.pageQuery(applied: applied, current: typedNow) != nil)
    }

    @Test func weekPagesWithTheOriginalBoundAsNowRolls() {
        // `.week` re-reads `.now` on every `since` access, so the query a
        // reload applied and the one loadMore builds moments later carry
        // different cutoffs. Identity is the period selection, so paging must
        // still pass — under the applied cutoff, never the re-derived one.
        let applied = DictationLibraryQuery(search: "", period: .week, sourceApp: nil)
        Thread.sleep(forTimeInterval: 0.05)
        let current = DictationLibraryQuery(search: "", period: .week, sourceApp: nil)

        #expect(applied.since != current.since)
        let page = DictationLibraryQuery.pageQuery(applied: applied, current: current)
        #expect(page != nil)
        #expect(page?.since == applied.since)
        #expect(page?.since != current.since)

        #expect(DictationLibraryQuery.pageQuery(
            applied: applied,
            current: DictationLibraryQuery(search: "", period: .all, sourceApp: nil))
            == nil)
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
