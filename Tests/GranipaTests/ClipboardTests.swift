import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct ClipboardTests {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    private func textItem(_ text: String, at date: Date = .now) -> ClipboardItem {
        ClipboardItem(
            id: UUID().uuidString, type: ClipboardClassifier.classify(text),
            textContent: text, imagePath: nil, sourceApp: "Test",
            createdAt: date, sizeBytes: text.utf8.count, width: nil, height: nil)
    }

    @Test func classifiesLinksAndText() {
        #expect(ClipboardClassifier.classify("https://example.com/x?a=1") == .link)
        #expect(ClipboardClassifier.classify("  http://foo.bar  ") == .link)
        #expect(ClipboardClassifier.classify("hola mundo") == .text)
        #expect(ClipboardClassifier.classify("see https://example.com today") == .text)
        #expect(ClipboardClassifier.classify("ftp://example.com") == .text)
    }

    @Test func insertFetchSearchAndFilter() throws {
        let db = try makeDatabase()
        try db.insertClipboardItem(textItem("hello world"))
        try db.insertClipboardItem(textItem("https://granola.ai"))

        let all = try db.fetchClipboardItems()
        #expect(all.count == 2)

        let links = try db.fetchClipboardItems(type: .link)
        #expect(links.count == 1)
        #expect(links[0].textContent == "https://granola.ai")

        let search = try db.fetchClipboardItems(search: "WORLD")
        #expect(search.count == 1)
        #expect(search[0].textContent == "hello world")

        #expect(try db.fetchClipboardItems(search: "100%").isEmpty)
    }

    @Test func pruneKeepsNewest() throws {
        let db = try makeDatabase()
        let base = Date.now
        for index in 0..<10 {
            try db.insertClipboardItem(
                textItem("item \(index)", at: base.addingTimeInterval(Double(index))))
        }
        let removedPaths = try db.pruneClipboardItems(keep: 4)
        #expect(removedPaths.isEmpty)

        let remaining = try db.fetchClipboardItems()
        #expect(remaining.count == 4)
        #expect(remaining.first?.textContent == "item 9")
        #expect(remaining.last?.textContent == "item 6")
    }

    @Test func deleteReturnsImagePath() throws {
        let db = try makeDatabase()
        let item = ClipboardItem(
            id: "img1", type: .image, textContent: nil,
            imagePath: "/tmp/img1.png", sourceApp: nil,
            createdAt: .now, sizeBytes: 100, width: 10, height: 10)
        try db.insertClipboardItem(item)
        let path = try db.deleteClipboardItem(id: "img1")
        #expect(path == "/tmp/img1.png")
        #expect(try db.fetchClipboardItems().isEmpty)
    }
}
