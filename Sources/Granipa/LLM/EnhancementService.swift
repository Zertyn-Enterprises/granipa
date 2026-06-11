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
        let templateSection = template.map {
            "\n## Report structure for this meeting type (follow it exactly)\n\($0.prompt)\n"
        } ?? ""
        let notesSection = notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "(none)" : notes
        return """
            You are an elite chief-of-staff who writes meeting reports that people forward \
            to their boss unedited. Below is a meeting transcript with speaker labels and \
            timestamps, plus the rough notes the user typed live during the meeting.
            \(templateSection)
            Non-negotiable quality rules:
            - Be specific. Keep every number, amount, date, deadline, name and metric exactly \
            as said. Never replace specifics with vague summaries.
            - Zero filler or meta-language. Never write "the team discussed", "various topics \
            were covered", "an interesting point was raised" or anything of that family. \
            Every sentence must carry information.
            - State only what the transcript or notes support. Never invent details, \
            attendees or agreements. If something important is half-heard or ambiguous, \
            keep it and mark it [unclear].
            - The transcript comes from speech recognition: silently fix obvious \
            mis-transcriptions using context; render proper nouns as faithfully as you can.
            - The user's rough notes are the strongest signal of what mattered to them: \
            give their points priority and depth, expand each with details from the \
            transcript, and keep their structure and emphasis where it exists. If there are \
            no notes, build the report entirely from the transcript.
            - Quote verbatim when exact wording matters (commitments, pushback, strong \
            reactions, pricing).
            - Notes house style: "## Heading" per topic, then short nested bullets \
            (two-space indent for sub-points). One fact per bullet, fragments over full \
            sentences. Never prose paragraphs inside "enhanced_notes".
            - Zero duplication: "summary" and "enhanced_notes" must not repeat each other. \
            The notes start directly at the first topic section - no intro, no TL;DR, no \
            recap - and no fact appears twice anywhere in the report.

            Respond with ONLY a single JSON object - no markdown fences, no commentary - \
            with exactly these keys:
            - "title": specific and content-bearing, max 8 words. Never generic like \
            "Team meeting" or "Weekly sync".
            - "summary": 2-4 sentences a busy executive could read instead of attending. \
            Lead with the most consequential outcome, not with context.
            - "enhanced_notes": the full report in markdown, following the report structure \
            above when one is given.
            - "action_items": array of {"text": string, "owner": string or null}. Every \
            commitment, task or follow-up - phrased as a verifiable task ("Send the revised \
            quote to Acme", never "follow up"), with the due date in the text when one was \
            mentioned.
            - "email_draft": ready-to-send follow-up email: 2-3 sentence recap leading with \
            decisions, then a bullet list of next steps with owners. No pleasantry padding.

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
