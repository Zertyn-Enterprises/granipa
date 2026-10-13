import CoreMedia
import Foundation
import Speech

/// SpeechTranscriber tags each run of a result with its audio time range when
/// asked for `.audioTimeRange`; those runs are the transcript's word timings.
enum TranscriptWords {
    static func from(_ text: AttributedString) -> [TranscriptWord]? {
        var words: [TranscriptWord] = []
        for run in text.runs {
            let word = String(text[run.range].characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Untimed punctuation rides on the word before it, so a filtered
            // segment rebuilt from its words keeps it; an untimed word means
            // the timings do not cover the text.
            guard let range = run.audioTimeRange else {
                if !letters(of: word).isEmpty { return nil }
                if !word.isEmpty, let last = words.indices.last {
                    words[last].text += word
                }
                continue
            }
            let start = range.start.seconds
            let end = range.end.seconds
            guard !word.isEmpty, start.isFinite, end.isFinite else { continue }
            words.append(TranscriptWord(text: word, start: start, end: end))
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
