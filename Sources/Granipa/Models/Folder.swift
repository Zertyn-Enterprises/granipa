import Foundation
import GRDB

struct Folder: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var id: String
    var name: String
    var team: String?
    var position: Int

    static func new(name: String, team: String?) -> Folder {
        Folder(
            id: UUID().uuidString,
            name: name,
            team: team?.trimmingCharacters(in: .whitespaces).isEmpty == false ? team : nil,
            position: 0)
    }
}
