import Foundation

struct ActionItem: Codable, Hashable, Sendable {
    var text: String
    var owner: String?

    static func decodeList(from json: String?) -> [ActionItem] {
        guard let json, let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ActionItem].self, from: data)) ?? []
    }

    static func encodeList(_ items: [ActionItem]) -> String? {
        guard !items.isEmpty, let data = try? JSONEncoder().encode(items) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
