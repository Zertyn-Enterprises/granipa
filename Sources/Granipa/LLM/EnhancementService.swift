import Foundation

struct EnhancementResult: Codable, Sendable {
    var title: String?
    var summary: String?
    var enhancedNotes: String?
    var actionItems: [ActionItem]?
    var emailDraft: String?

    enum CodingKeys: String, CodingKey {
        case title
        case summary
        case enhancedNotes = "enhanced_notes"
        case actionItems = "action_items"
        case emailDraft = "email_draft"
    }
}

enum EnhancementError: LocalizedError {
    case noJSONObject

    var errorDescription: String? {
        "The model response did not contain a JSON object."
    }
}

enum EnhancementService {
    static func transcriptText(segments: [TranscriptSegment]) -> String {
        segments
            .sorted { $0.startSeconds < $1.startSeconds }
            .map { segment in
                let total = Int(segment.startSeconds)
                let stamp = String(format: "%d:%02d", total / 60, total % 60)
                return "[\(stamp)] \(segment.speaker): \(segment.text)"
            }
            .joined(separator: "\n")
    }

    static func buildPrompt(template: MeetingTemplate?, notes: String, transcript: String) -> String {
        let templateSection = template.map { "\nMeeting type guidance: \($0.prompt)\n" } ?? ""
        let notesSection = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(none)" : notes
        return """
            You are an expert meeting-notes assistant. Below is a meeting transcript with \
            speaker labels and timestamps, plus the user's own rough notes taken during the \
            meeting.
            \(templateSection)
            Respond with ONLY a single JSON object - no markdown fences, no commentary - \
            with exactly these keys:
            - "title": a short descriptive meeting title (max 8 words).
            - "summary": 2-4 sentence summary of the meeting.
            - "enhanced_notes": well-structured markdown notes. The user's rough notes are \
            the backbone: keep their structure, wording and emphasis, expand abbreviations, \
            and fill in gaps and details from the transcript. If the user took no notes, \
            build the notes entirely from the transcript.
            - "action_items": array of {"text": string, "owner": string or null} with every \
            concrete commitment, task or follow-up mentioned.
            - "email_draft": a short, ready-to-send follow-up email summarizing decisions \
            and next steps.

            Write all output in the dominant language of the meeting (e.g. English or Spanish).

            ## User's rough notes
            \(notesSection)

            ## Transcript
            \(transcript)
            """
    }

    static func parse(_ raw: String) throws -> EnhancementResult {
        guard
            let start = raw.firstIndex(of: "{"),
            let end = raw.lastIndex(of: "}"),
            start < end
        else {
            throw EnhancementError.noJSONObject
        }
        let json = String(raw[start...end])
        return try JSONDecoder().decode(EnhancementResult.self, from: Data(json.utf8))
    }
}
