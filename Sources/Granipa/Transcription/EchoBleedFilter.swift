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
    /// Echo comes after its source; word times are interpolated across their
    /// segment, so the mic word may trail the system word by up to this much…
    static let wordToleranceSeconds = 4.0
    /// …and appear to lead it by at most this interpolation slack.
    static let earlySlackSeconds = 1.0
    /// With recognizer word timings, echo trails its source by the acoustic
    /// path plus timestamp jitter; a genuine read-back trails by a whole turn.
    static let preciseLagRange: ClosedRange<Double> = -0.25...0.8
    /// Below this share of mic words the meeting most likely had no speaker
    /// bleed (headphones), and exact repeats are the user's own read-backs.
    static let minimumBleedShare = 0.25
    /// One file per rewriting pass (a meeting can be recorded again), so
    /// every pre-filter version survives.
    static func backupFileName(meetingID: String, date: Date = .now) -> String {
        "\(meetingID)-mic-before-bleed-filter-\(Int(date.timeIntervalSince1970 * 1000)).json"
    }

    /// Rewrites the mic channel only after saving the original segments to
    /// the backup directory; without one nothing changes.
    static func apply(meetingID: String, database: AppDatabase, backupDirectory: URL?) throws {
        guard let backupDirectory else { return }
        let segments = try database.fetchSegments(meetingID: meetingID)
        let mic = segments.filter { $0.channel == .mic }
        let system = segments.filter { $0.channel == .system && $0.isFinal }
        let cleaned = clean(mic: mic, system: system)
        guard cleaned != mic else { return }
        let backup = backupDirectory.appendingPathComponent(backupFileName(meetingID: meetingID))
        try JSONEncoder().encode(mic).write(to: backup, options: .atomic)
        try database.replaceSegments(meetingID: meetingID, channel: .mic, with: cleaned)
    }

    /// Deleting a meeting must not leave its transcript behind.
    static func removeBackups(meetingID: String, from backupDirectory: URL?) {
        guard let backupDirectory,
            let names = try? FileManager.default.contentsOfDirectory(atPath: backupDirectory.path)
        else { return }
        for name in names where name.hasPrefix("\(meetingID)-mic-before-bleed-filter") {
            try? FileManager.default.removeItem(at: backupDirectory.appendingPathComponent(name))
        }
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

        return zip(mic, masks).flatMap { segment, mask -> [TranscriptSegment] in
            guard let mask, mask.contains(true) else { return [segment] }
            return keptPieces(of: segment, mask: mask)
        }
    }

    /// Each contiguous run of kept tokens becomes a segment whose bounds are
    /// those tokens' interpolated span, so seek and export stay on real speech.
    private static func keptPieces(of segment: TranscriptSegment, mask: [Bool])
        -> [TranscriptSegment]
    {
        let tokens = timedTokens(segment)
        var runs: [[TimedToken]] = []
        var current: [TimedToken] = []
        for (token, dropped) in zip(tokens, mask) {
            if dropped {
                if !current.isEmpty { runs.append(current) }
                current = []
            } else {
                current.append(token)
            }
        }
        if !current.isEmpty { runs.append(current) }
        let kept = runs.filter { $0.contains { !$0.word.isEmpty } }
        return kept.enumerated().map { index, run in
            var piece = segment
            if index > 0 { piece.id = UUID().uuidString }
            piece.text = run.map { String($0.token) }.joined(separator: " ")
            piece.startSeconds = run.first?.start ?? segment.startSeconds
            piece.endSeconds = run.last?.end ?? segment.endSeconds
            if segment.words != nil {
                piece.words = run.map {
                    TranscriptWord(text: String($0.token), start: $0.start, end: $0.end)
                }
            }
            return piece
        }
    }

    private struct TimedToken {
        let token: Substring
        let word: String
        let start: Double
        let end: Double
        /// Recognizer timing rather than an interpolated guess.
        let isPrecise: Bool
        var seconds: Double { (start + end) / 2 }
    }

    private static func timedTokens(_ segment: TranscriptSegment) -> [TimedToken] {
        if let words = segment.words, !words.isEmpty {
            return words.map {
                TimedToken(
                    token: Substring($0.text), word: normalized(Substring($0.text)),
                    start: $0.start, end: $0.end, isPrecise: true)
            }
        }
        let tokens = segment.text.split(whereSeparator: \.isWhitespace)
        let span = max(segment.endSeconds - segment.startSeconds, 0)
        let step = tokens.isEmpty ? 0 : span / Double(tokens.count)
        return tokens.enumerated().map { index, token in
            TimedToken(
                token: token,
                word: normalized(token),
                start: segment.startSeconds + step * Double(index),
                end: segment.startSeconds + step * Double(index + 1),
                isPrecise: false)
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
                isCausalEcho(mine[start + length], of: heard[offset + length])
            {
                length += 1
            }
            best = max(best, length)
        }
        return best
    }

    private static func isCausalEcho(_ mine: TimedToken, of heard: TimedToken) -> Bool {
        if mine.isPrecise, heard.isPrecise {
            return preciseLagRange.contains(mine.start - heard.start)
        }
        let lag = mine.seconds - heard.seconds
        return lag >= -earlySlackSeconds && lag <= wordToleranceSeconds
    }

    static func normalized(_ token: Substring) -> String {
        token.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .filter { $0.isLetter || $0.isNumber }
    }
}
