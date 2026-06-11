import Foundation
import GRDB

enum ClipboardItemType: String, Codable, Sendable, CaseIterable {
    case text
    case link
    case image
    case file
}

struct ClipboardItem: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var id: String
    var type: ClipboardItemType
    var textContent: String?
    var imagePath: String?
    var sourceApp: String?
    var createdAt: Date
    var sizeBytes: Int?
    var width: Int?
    var height: Int?
}

enum ClipboardClassifier {
    static func classify(_ string: String) -> ClipboardItemType {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
            let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https"
        else {
            return .text
        }
        return .link
    }
}
