import CoreMedia
import Foundation
import Speech

/// SpeechTranscriber tags each run of a result with its audio time range when
/// asked for `.audioTimeRange`; those runs are the transcript's word timings.
enum TranscriptWords {
    static func from(_ text: AttributedString) -> [TranscriptWord]? {
        var words: [TranscriptWord] = []
        var opening = ""
        for run in text.runs {
            let raw = String(text[run.range].characters)
            let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            // Untimed punctuation joins the word it touches, so a filtered
            // segment rebuilt from its words keeps it: text glued to the
            // previous word closes it ("tal?"), text after a space opens the
            // next one ("¿Qué"). An untimed word means the timings do not
            // cover the text.
            guard let range = run.audioTimeRange else {
                if !letters(of: word).isEmpty { return nil }
                var chunks = raw.split(whereSeparator: \.isWhitespace).map(String.init)
                if let first = raw.first, !first.isWhitespace, let last = words.indices.last,
                    !chunks.isEmpty
                {
                    words[last].text += chunks.removeFirst()
                }
                opening += chunks.joined()
                continue
            }
            let start = range.start.seconds
            let end = range.end.seconds
            guard !word.isEmpty, start.isFinite, end.isFinite else { continue }
            words.append(TranscriptWord(text: opening + word, start: start, end: end))
            opening = ""
        }
        if !opening.isEmpty, let last = words.indices.last {
            words[last].text += opening
        }
        // Partial tagging would drop untagged words when a filtered segment
        // is rebuilt from its words, so only a full cover is kept.
        guard !words.isEmpty,
            letters(of: words.map(\.text).joined()) == letters(of: String(text.characters))
        else { return nil }
        return words
    }

    private static func letters(of text: String) -> String {
        String(text.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) })
    }
}
