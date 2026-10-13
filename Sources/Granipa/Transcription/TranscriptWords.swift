import CoreMedia
import Foundation
import Speech

/// SpeechTranscriber tags each run of a result with its audio time range when
/// asked for `.audioTimeRange`; those runs are the transcript's word timings.
enum TranscriptWords {
    static func from(_ text: AttributedString) -> [TranscriptWord]? {
        var words: [TranscriptWord] = []
        for run in text.runs {
            guard let range = run.audioTimeRange else { continue }
            let word = String(text[run.range].characters)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let start = range.start.seconds
            let end = range.end.seconds
            guard !word.isEmpty, start.isFinite, end.isFinite else { continue }
            words.append(TranscriptWord(text: word, start: start, end: end))
        }
        return words.isEmpty ? nil : words
    }
}
