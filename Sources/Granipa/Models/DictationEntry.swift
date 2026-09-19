import Foundation
import GRDB

struct DictationEntry: Codable, Identifiable, Hashable, Sendable, FetchableRecord,
    PersistableRecord
{
    var id: String
    var text: String
    var createdAt: Date
    var durationSeconds: Double
    var wordCount: Int
    var sourceApp: String?

    static func new(text: String, durationSeconds: Double, sourceApp: String?) -> DictationEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return DictationEntry(
            id: UUID().uuidString,
            text: trimmed,
            createdAt: .now,
            durationSeconds: max(0, durationSeconds),
            wordCount: DictationStats.wordCount(in: trimmed),
            sourceApp: sourceApp)
    }
}

/// One consistent read of the history screen: page, total, stats and app list.
struct DictationLibrarySnapshot: Sendable {
    var entries: [DictationEntry]
    var total: Int
    var stats: DictationStats
    var sourceApps: [String]
}

struct DictationStats: Equatable, Sendable {
    var words: Int
    var durationSeconds: Double
    var apps: Int

    /// Average speaking speed. Zero if nothing was timed.
    var averageWPM: Int {
        guard durationSeconds > 0.5 else { return 0 }
        return Int((Double(words) / (durationSeconds / 60)).rounded())
    }

    /// Time it would take to type these words at 40 WPM.
    var timeSavedSeconds: Double {
        Double(words) / 40 * 60
    }

    static let empty = DictationStats(words: 0, durationSeconds: 0, apps: 0)

    static func wordCount(in text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    func savedLabel() -> String {
        let seconds = timeSavedSeconds
        if seconds >= 3600 {
            let hours = seconds / 3600
            if hours >= 10 { return String(format: "%.0f hours", hours) }
            return String(format: "%.1f hours", hours)
        }
        if seconds >= 60 {
            return "\(Int((seconds / 60).rounded())) min"
        }
        return "\(Int(seconds.rounded()))s"
    }
}
