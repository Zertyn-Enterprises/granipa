import Foundation

/// In-meeting transcript filter and talk-time. Search is a case-insensitive
/// substring of already-loaded rows — not `AppDatabase.searchMeetings`, which
/// is a meeting-level LIKE across title/notes/transcript and treats `%`/`_`
/// as wildcards.
enum TranscriptQuery {
    static func normalizedQuery(_ query: String) -> String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func filter(
        segments: [TranscriptSegment],
        query: String,
        speaker: String?
    ) -> [TranscriptSegment] {
        let needle = normalizedQuery(query)
        return segments.filter { segment in
            if let speaker, segment.speaker != speaker { return false }
            if needle.isEmpty { return true }
            return segment.text.localizedCaseInsensitiveContains(needle)
                || segment.speaker.localizedCaseInsensitiveContains(needle)
        }
    }

    static func speakers(in segments: [TranscriptSegment]) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for segment in segments where seen.insert(segment.speaker).inserted {
            ordered.append(segment.speaker)
        }
        return ordered
    }

    /// Segments whose half-open interval `[start, end)` contains `seconds`.
    /// At a segment's exact end the next row owns the boundary, except when
    /// `seconds` is the last end in the list (EOF), which keeps that row.
    static func containing(
        _ segments: [TranscriptSegment],
        at seconds: Double
    ) -> [TranscriptSegment] {
        guard seconds.isFinite else { return [] }
        let hits = segments.filter { segment in
            guard let (lo, hi) = bounds(of: segment), hi > lo else { return false }
            return seconds >= lo && seconds < hi
        }
        if !hits.isEmpty { return hits }
        let lastEnd = segments.compactMap { bounds(of: $0)?.hi }.max()
        guard lastEnd == seconds else { return [] }
        return segments.filter { segment in
            guard let (lo, hi) = bounds(of: segment) else { return false }
            return hi == seconds && lo <= seconds
        }
    }

    private static func bounds(of segment: TranscriptSegment) -> (lo: Double, hi: Double)? {
        guard segment.startSeconds.isFinite, segment.endSeconds.isFinite else { return nil }
        return (
            lo: min(segment.startSeconds, segment.endSeconds),
            hi: max(segment.startSeconds, segment.endSeconds))
    }
}

enum SpeakerTalkTime {
    struct Row: Equatable, Sendable {
        let speaker: String
        let seconds: Double
        /// Share of summed per-speaker seconds, not of wall-clock duration.
        let share: Double
    }

    struct Report: Equatable, Sendable {
        let rows: [Row]
        let summedSeconds: Double
        let unionSeconds: Double
        /// True when at least two speakers overlap in time, so shares are of
        /// talking-time rather than exclusive meeting time.
        let hasOverlap: Bool
    }

    static func report(segments: [TranscriptSegment]) -> Report {
        var intervals: [String: [(Double, Double)]] = [:]
        for segment in segments {
            guard segment.startSeconds.isFinite, segment.endSeconds.isFinite else { continue }
            let lo = min(segment.startSeconds, segment.endSeconds)
            let hi = max(segment.startSeconds, segment.endSeconds)
            guard hi > lo else { continue }
            intervals[segment.speaker, default: []].append((lo, hi))
        }

        var rows: [Row] = []
        rows.reserveCapacity(intervals.count)
        var summed = 0.0
        for (speaker, ranges) in intervals {
            let seconds = mergedDuration(ranges)
            guard seconds > 0 else { continue }
            rows.append(Row(speaker: speaker, seconds: seconds, share: 0))
            summed += seconds
        }
        let union = mergedDuration(intervals.values.flatMap { $0 })
        let hasOverlap = summed > union + 0.000_5
        rows = rows
            .map { Row(speaker: $0.speaker, seconds: $0.seconds, share: summed > 0 ? $0.seconds / summed : 0) }
            .sorted { lhs, rhs in
                if lhs.speaker == "Me" && rhs.speaker != "Me" { return true }
                if rhs.speaker == "Me" && lhs.speaker != "Me" { return false }
                if lhs.seconds != rhs.seconds { return lhs.seconds > rhs.seconds }
                return lhs.speaker.localizedStandardCompare(rhs.speaker) == .orderedAscending
            }
        return Report(
            rows: rows, summedSeconds: summed, unionSeconds: union, hasOverlap: hasOverlap)
    }

    private static func mergedDuration(_ ranges: [(Double, Double)]) -> Double {
        let sorted = ranges.sorted { $0.0 < $1.0 || ($0.0 == $1.0 && $0.1 < $1.1) }
        var total = 0.0
        var currentLo: Double?
        var currentHi: Double?
        for (lo, hi) in sorted {
            if let start = currentLo, let end = currentHi {
                if lo <= end {
                    currentHi = max(end, hi)
                } else {
                    total += end - start
                    currentLo = lo
                    currentHi = hi
                }
            } else {
                currentLo = lo
                currentHi = hi
            }
        }
        if let start = currentLo, let end = currentHi {
            total += end - start
        }
        return total
    }
}
