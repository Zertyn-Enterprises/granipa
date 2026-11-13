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
    /// One file per rewriting pass, so every pre-filter version survives.
    static func backupFileName(meetingID: String, date: Date = .now) -> String {
        "\(meetingID)-mic-before-bleed-filter-\(Int(date.timeIntervalSince1970 * 1000)).json"
    }

    /// Rewrites the mic channel only after saving the original segments to
    /// the backup directory; without one nothing changes. Segments without
    /// recognizer word timings are matched only when `allowCoarseTiming` —
    /// an explicit user request — since interpolated times can mistake a
    /// read-back for echo. `earlierPassIDs` are segments recorded before this
    /// pass: their times restart at zero too, so they are never compared.
    /// Returns whether the mic transcript was rewritten.
    @discardableResult
    static func apply(
        meetingID: String, database: AppDatabase, backupDirectory: URL?,
        allowCoarseTiming: Bool = false, earlierPassIDs: Set<String> = []
    ) throws -> Bool {
        guard let backupDirectory else { return false }
        let segments = try database.fetchSegments(meetingID: meetingID)
            .filter { !earlierPassIDs.contains($0.id) }
        let mic = segments.filter { $0.channel == .mic }
        let system = segments.filter { $0.channel == .system && $0.isFinal }
        let cleaned = clean(mic: mic, system: system, allowCoarseTiming: allowCoarseTiming)
        guard cleaned != mic else { return false }
        let backup = backupDirectory.appendingPathComponent(backupFileName(meetingID: meetingID))
        try JSONEncoder().encode(mic).write(to: backup, options: .atomic)
        guard try database.replaceSegments(mic, with: cleaned) else {
            // Another pass or an edit changed these rows since the fetch.
            try? FileManager.default.removeItem(at: backup)
            return false
        }
        return true
    }

    /// Deleting a meeting must not leave its transcript behind; a failure is
    /// thrown so the caller can keep the meeting and let the user retry.
    static func removeBackups(meetingID: String, from backupDirectory: URL?) throws {
        guard let backupDirectory,
            FileManager.default.fileExists(atPath: backupDirectory.path)
        else { return }
        let names = try FileManager.default.contentsOfDirectory(atPath: backupDirectory.path)
        for name in names where name.hasPrefix("\(meetingID)-mic-before-bleed-filter") {
            try FileManager.default.removeItem(at: backupDirectory.appendingPathComponent(name))
        }
    }

    /// A delete that ran while a pass was in flight removed the backups
    /// before the pass wrote its own; this drops that orphan afterwards.
    static func removeOrphanedBackups(
        meetingID: String, database: AppDatabase, backupDirectory: URL?
    ) throws {
        guard try database.fetchMeeting(id: meetingID) == nil else { return }
        try removeBackups(meetingID: meetingID, from: backupDirectory)
    }

    static func clean(
        mic: [TranscriptSegment], system: [TranscriptSegment], allowCoarseTiming: Bool = false
    ) -> [TranscriptSegment] {
        // Every recording pass restarts meeting time at zero; overlapping
        // segments on one channel mean several passes whose times collide.
        guard !hasOverlappingPasses(mic), !hasOverlappingPasses(system) else { return mic }
        let masks = mic.map {
            dropMask(for: $0, system: system, allowCoarseTiming: allowCoarseTiming)
        }
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
    static let passOverlapSeconds = 1.0

    private static func hasOverlappingPasses(_ segments: [TranscriptSegment]) -> Bool {
        let ordered = segments.sorted { $0.startSeconds < $1.startSeconds }
        return zip(ordered, ordered.dropFirst()).contains {
            $1.startSeconds < $0.endSeconds - passOverlapSeconds
        }
    }

    private static func dropMask(
        for segment: TranscriptSegment, system: [TranscriptSegment], allowCoarseTiming: Bool
    ) -> [Bool]? {
        let overlapping = system
            .filter {
                $0.startSeconds <= segment.endSeconds + windowSeconds
                    && $0.endSeconds >= segment.startSeconds - windowSeconds
            }
        if !allowCoarseTiming,
            segment.words == nil || overlapping.contains(where: { $0.words == nil })
        {
            return nil
        }
        let heard = overlapping
            .sorted { $0.startSeconds < $1.startSeconds }
            .flatMap(timedTokens)
            .filter { !$0.word.isEmpty }
        guard !heard.isEmpty else { return nil }
        let mine = timedTokens(segment)
        let runs = echoRuns(mine: mine, heard: heard)
        var drop = Array(repeating: false, count: mine.count)
        for run in runs {
            for position in run.mine..<(run.mine + run.length) { drop[position] = true }
        }
        for (before, after) in zip(runs, runs.dropFirst())
        where isMisheardGap(before, after, mine: mine, heard: heard) {
            for position in (before.mine + before.length)..<after.mine { drop[position] = true }
        }
        return drop
    }

    /// A run of mic tokens starting at `mine` that repeats `heard` from `heard`.
    private struct EchoRun {
        let mine: Int
        let heard: Int
        let length: Int
    }

    private static func echoRuns(mine: [TimedToken], heard: [TimedToken]) -> [EchoRun] {
        var runs: [EchoRun] = []
        var index = 0
        while index < mine.count {
            let run = longestRun(from: index, in: mine, heard: heard)
            if run.length >= minRun {
                runs.append(run)
                index += run.length
            } else {
                index += 1
            }
        }
        return runs
    }

    /// Mic words between two echo runs are misheard echo only when the system
    /// said other words between the runs' sources too, each mic word timed as
    /// an echo of one of them. Back-to-back sources mean the mic words were
    /// inserted, and an untimely word was said in a pause: the user's own.
    private static func isMisheardGap(
        _ before: EchoRun, _ after: EchoRun, mine: [TimedToken], heard: [TimedToken]
    ) -> Bool {
        let gap = (before.mine + before.length)..<after.mine
        let heardStart = before.heard + before.length
        guard (1...maxBridgedGap).contains(gap.count),
            (1...maxBridgedGap).contains(after.heard - heardStart)
        else { return false }
        let sources = heard[heardStart..<after.heard]
        return gap.allSatisfy { position in
            sources.contains { isCausalEcho(mine[position], of: $0) }
        }
    }

    private static func longestRun(from start: Int, in mine: [TimedToken], heard: [TimedToken])
        -> EchoRun
    {
        var best = EchoRun(mine: start, heard: 0, length: 0)
        guard !mine[start].word.isEmpty else { return best }
        for offset in heard.indices {
            var length = 0
            while start + length < mine.count, offset + length < heard.count,
                mine[start + length].word == heard[offset + length].word,
                isCausalEcho(mine[start + length], of: heard[offset + length])
            {
                length += 1
            }
            if length > best.length { best = EchoRun(mine: start, heard: offset, length: length) }
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
