import Foundation

/// Meetings record the mic without echo cancellation (voice processing pegged a
/// core and hung Record), so with the Mac's speakers on, the other side plays
/// into the mic and the "Me" transcript repeats what the system channel heard.
/// Runs of consecutive words the system channel said at about the same time are
/// removed from mic segments, plus short misheard gaps between such runs.
/// Words only the mic heard — the user's own — stay.
enum EchoBleedFilter {
    static let minRun = 3
    static let maxBridgedGap = 2
    static let windowSeconds = 1.5
    /// Word times are interpolated across their segment, so matches allow slack.
    static let wordToleranceSeconds = 4.0
    /// Below this share of mic words the meeting most likely had no speaker
    /// bleed (headphones), and exact repeats are the user's own read-backs.
    static let minimumBleedShare = 0.25
    static let backupFileName = "mic-transcript-before-bleed-filter.json"

    /// Rewrites the mic channel only after saving the original segments next
    /// to the meeting audio; without a backup directory nothing changes.
    static func apply(meetingID: String, database: AppDatabase, backupDirectory: URL?) throws {
        guard let backupDirectory else { return }
        let segments = try database.fetchSegments(meetingID: meetingID)
        let mic = segments.filter { $0.channel == .mic }
        let system = segments.filter { $0.channel == .system && $0.isFinal }
        let cleaned = clean(mic: mic, system: system)
        guard cleaned != mic else { return }
        let backup = backupDirectory.appendingPathComponent(backupFileName)
        if !FileManager.default.fileExists(atPath: backup.path) {
            try JSONEncoder().encode(mic).write(to: backup, options: .atomic)
        }
        try database.replaceSegments(meetingID: meetingID, channel: .mic, with: cleaned)
    }

    static func clean(mic: [TranscriptSegment], system: [TranscriptSegment]) -> [TranscriptSegment] {
        let masks = mic.map { dropMask(for: $0, system: system) }
        var words = 0
        var bleed = 0
        for (segment, mask) in zip(mic, masks) {
            let tokens = timedTokens(segment)
            words += tokens.filter { !$0.word.isEmpty }.count
            if let mask {
                bleed += zip(tokens, mask).filter { !$0.0.word.isEmpty && $0.1 }.count
            }
        }
        guard words > 0, Double(bleed) / Double(words) >= minimumBleedShare else { return mic }

        return zip(mic, masks).compactMap { segment, mask in
            guard let mask, mask.contains(true) else { return segment }
            let kept = zip(timedTokens(segment), mask).filter { !$0.1 }.map(\.0)
            guard kept.contains(where: { !$0.word.isEmpty }) else { return nil }
            var copy = segment
            copy.text = kept.map { String($0.token) }.joined(separator: " ")
            return copy
        }
    }

    private struct TimedToken {
        let token: Substring
        let word: String
        let seconds: Double
    }

    private static func timedTokens(_ segment: TranscriptSegment) -> [TimedToken] {
        let tokens = segment.text.split(whereSeparator: \.isWhitespace)
        let span = max(segment.endSeconds - segment.startSeconds, 0)
        return tokens.enumerated().map { index, token in
            TimedToken(
                token: token,
                word: normalized(token),
                seconds: segment.startSeconds
                    + span * (Double(index) + 0.5) / Double(tokens.count))
        }
    }

    /// nil when no system speech overlaps the segment.
    private static func dropMask(
        for segment: TranscriptSegment, system: [TranscriptSegment]
    ) -> [Bool]? {
        let heard = system
            .filter {
                $0.startSeconds <= segment.endSeconds + windowSeconds
                    && $0.endSeconds >= segment.startSeconds - windowSeconds
            }
            .sorted { $0.startSeconds < $1.startSeconds }
            .flatMap(timedTokens)
            .filter { !$0.word.isEmpty }
        guard !heard.isEmpty else { return nil }
        let mine = timedTokens(segment)
        var drop = Array(repeating: false, count: mine.count)
        var index = 0
        while index < mine.count {
            let run = longestRun(from: index, in: mine, heard: heard)
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
        return drop
    }

    private static func longestRun(from start: Int, in mine: [TimedToken], heard: [TimedToken])
        -> Int
    {
        guard !mine[start].word.isEmpty else { return 0 }
        var best = 0
        for offset in heard.indices {
            var length = 0
            while start + length < mine.count, offset + length < heard.count,
                mine[start + length].word == heard[offset + length].word,
                abs(mine[start + length].seconds - heard[offset + length].seconds)
                    <= wordToleranceSeconds
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
