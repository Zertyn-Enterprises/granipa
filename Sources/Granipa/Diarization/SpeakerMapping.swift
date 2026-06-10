import Foundation

struct SpeakerSpan: Hashable, Sendable {
    let speakerID: String
    let start: Double
    let end: Double
}

enum SpeakerMapping {
    static func relabel(segments: [TranscriptSegment], spans: [SpeakerSpan]) -> [TranscriptSegment] {
        segments.map { segment in
            var overlaps: [String: Double] = [:]
            for span in spans {
                let overlap = min(segment.endSeconds, span.end) - max(segment.startSeconds, span.start)
                if overlap > 0 {
                    overlaps[span.speakerID, default: 0] += overlap
                }
            }
            let duration = max(segment.endSeconds - segment.startSeconds, 0.001)
            guard
                let best = overlaps.max(by: { $0.value < $1.value }),
                best.value >= duration * 0.2
            else {
                return segment
            }
            var copy = segment
            copy.speaker = "Speaker \(best.key)"
            return copy
        }
    }

    static func nameInferencePrompt(transcript: String, speakerLabels: [String]) -> String {
        """
        Below is a meeting transcript. "Me" is the user. Speakers labeled \
        \(speakerLabels.joined(separator: ", ")) are remote participants whose real names \
        are unknown. Infer their names from context: introductions, greetings, people \
        addressing each other by name.

        Respond with ONLY a JSON object mapping each speaker label to a real name or null. \
        Use a name only when you are confident; otherwise use null. Example: \
        {"Speaker 1": "Maria", "Speaker 2": null}

        ## Transcript
        \(transcript)
        """
    }

    static func parseNames(_ raw: String, speakerLabels: [String]) -> [String: String] {
        guard
            let start = raw.firstIndex(of: "{"),
            let end = raw.lastIndex(of: "}"),
            start < end,
            let decoded = try? JSONDecoder().decode(
                [String: String?].self, from: Data(String(raw[start...end]).utf8))
        else {
            return [:]
        }
        var names: [String: String] = [:]
        for label in speakerLabels {
            guard
                let value = decoded[label] ?? nil,
                case let name = value.trimmingCharacters(in: .whitespacesAndNewlines),
                !name.isEmpty,
                name.count <= 40,
                !["null", "unknown", "n/a", "desconocido"].contains(name.lowercased())
            else { continue }
            names[label] = name
        }
        return names
    }

    static func applyNames(_ names: [String: String], to segments: [TranscriptSegment]) -> [TranscriptSegment] {
        guard !names.isEmpty else { return segments }
        return segments.map { segment in
            guard let name = names[segment.speaker] else { return segment }
            var copy = segment
            copy.speaker = name
            return copy
        }
    }
}
