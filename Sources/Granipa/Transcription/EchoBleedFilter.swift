import Foundation

/// Meetings record the mic without echo cancellation (voice processing pegged a
/// core and hung Record), so with the Mac's speakers on, the other side plays
/// into the mic and the "Me" transcript repeats what the system channel heard.
/// Runs of consecutive words the system channel said in the same time window
/// are removed from mic segments, plus short misheard gaps between such runs.
/// Words only the mic heard — the user's own — stay.
enum EchoBleedFilter {
    static let minRun = 3
    static let maxBridgedGap = 2
    static let windowSeconds = 1.5

    static func apply(meetingID: String, database: AppDatabase) throws {
        let segments = try database.fetchSegments(meetingID: meetingID)
        let mic = segments.filter { $0.channel == .mic }
        let system = segments.filter { $0.channel == .system && $0.isFinal }
        let cleaned = clean(mic: mic, system: system)
        guard cleaned != mic else { return }
        try database.replaceSegments(meetingID: meetingID, channel: .mic, with: cleaned)
    }

    static func clean(mic: [TranscriptSegment], system: [TranscriptSegment]) -> [TranscriptSegment] {
        mic.compactMap { segment in
            let heard = system
                .filter {
                    $0.startSeconds <= segment.endSeconds + windowSeconds
                        && $0.endSeconds >= segment.startSeconds - windowSeconds
                }
                .flatMap { $0.text.split(whereSeparator: \.isWhitespace).map(normalized) }
                .filter { !$0.isEmpty }
            guard !heard.isEmpty,
                let kept = keptTokens(of: segment.text, heard: heard)
            else { return segment }
            guard kept.contains(where: { !normalized($0).isEmpty }) else { return nil }
            var copy = segment
            copy.text = kept.joined(separator: " ")
            return copy
        }
    }

    /// nil when nothing in the text was bleed.
    private static func keptTokens(of text: String, heard: [String]) -> [Substring]? {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        let words = tokens.map(normalized)
        var drop = Array(repeating: false, count: tokens.count)
        var index = 0
        while index < words.count {
            let run = longestRun(from: index, in: words, heard: heard)
            if run >= minRun {
                for position in index..<(index + run) { drop[position] = true }
                index += run
            } else {
                index += 1
            }
        }
        let dropped = drop.indices.filter { drop[$0] }
        for (lower, upper) in zip(dropped, dropped.dropFirst())
        where upper - lower > 1 && upper - lower - 1 <= maxBridgedGap {
            for position in (lower + 1)..<upper { drop[position] = true }
        }
        if !drop.contains(true) { return nil }
        return tokens.indices.filter { !drop[$0] }.map { tokens[$0] }
    }

    private static func longestRun(from start: Int, in words: [String], heard: [String]) -> Int {
        guard !words[start].isEmpty else { return 0 }
        var best = 0
        for offset in heard.indices where heard[offset] == words[start] {
            var length = 0
            while start + length < words.count, offset + length < heard.count,
                words[start + length] == heard[offset + length]
            {
                length += 1
            }
            best = max(best, length)
        }
        return best
    }

    static func normalized(_ token: Substring) -> String {
        token.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}
