import Foundation
import GRDB

struct MeetingTemplate: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var id: String
    var name: String
    var prompt: String
    var isBuiltin: Bool

    static let builtins: [MeetingTemplate] = [
        MeetingTemplate(
            id: "builtin-general",
            name: "General",
            prompt: """
                Sections, in this order. Omit a section only when it is truly empty:

                ## TL;DR — 2-3 bullets with the outcomes that matter most.
                ## Decisions — every decision made, who made it, and the reasoning given.
                ## Key points — the substance of the discussion grouped by topic, each topic \
                opening with a short bold lead-in. Capture positions, numbers and tradeoffs \
                discussed — not topic labels.
                ## Risks & concerns — anything flagged as a problem, worry or blocker.
                ## Open questions — each unresolved item with who owns finding the answer.
                """,
            isBuiltin: true),
        MeetingTemplate(
            id: "builtin-one-on-one",
            name: "1:1",
            prompt: """
                This is a one-on-one. Capture the relationship, not just the agenda:

                ## Updates — what each person reported, kept separate per person.
                ## Feedback — feedback given in either direction, as close to verbatim as useful.
                ## Growth & career — any discussion of development, aspirations, compensation \
                or role changes.
                ## Concerns & signals — frustrations, morale signals, hesitations. Quote the \
                key phrasing; these subtleties are the most valuable part of a 1:1 record.
                ## Commitments — what each person committed to before the next 1:1, by person.
                """,
            isBuiltin: true),
        MeetingTemplate(
            id: "builtin-standup",
            name: "Standup",
            prompt: """
                Team standup. Keep it telegraphic — fragments over sentences, zero padding.

                Per person, in speaking order:
                **Name** — Done: … · Next: … · Blockers: …

                Then:
                ## Blockers requiring action — every blocker with who can unblock it. \
                Highlight anything that sounds blocked for more than a day.
                ## Cross-dependencies — who is waiting on whom, and for what.
                """,
            isBuiltin: true),
        MeetingTemplate(
            id: "builtin-sales",
            name: "Sales call",
            prompt: """
                Sales call. Build the deal record a top account executive would write:

                ## Snapshot — company, attendees (name, role), and deal stage after this call.
                ## Pain & need — the prospect's problems in their own words; quote the 1-2 \
                strongest statements verbatim.
                ## Qualification — what was learned about budget, decision authority, buying \
                process, timeline and success criteria — and explicitly what is still unknown.
                ## Objections & answers — each objection, how it was handled, and whether the \
                answer landed.
                ## Competition — competitors mentioned and how the prospect perceives them.
                ## Risks — anything that threatens this deal.
                ## Next steps — agreed actions with owner and date. This is the most important \
                section: be exact.

                Write the email_draft as a follow-up TO THE PROSPECT: thank them, recap the \
                value in their terms, confirm the agreed next steps.
                """,
            isBuiltin: true),
        MeetingTemplate(
            id: "builtin-interview",
            name: "Interview",
            prompt: """
                Job interview debrief. Produce an evidence-based assessment, not impressions:

                ## Candidate snapshot — role interviewed for and background highlights as \
                discussed in the conversation.
                ## Evidence by topic — for each question or area: what was asked, the substance \
                of the answer, and its quality (depth, specifics, structure). Use direct quotes \
                for standout moments, good or bad.
                ## Strengths — each backed by specific evidence from the conversation.
                ## Concerns & gaps — including evasive or shallow answers. Distinguish "answered \
                poorly" from "was never asked".
                ## Candidate's questions — what they asked and what it signals about their \
                priorities.
                ## Recommendation inputs — the facts that should weigh on the decision. Do NOT \
                invent a verdict the interviewer did not state.
                """,
            isBuiltin: true),
        MeetingTemplate(
            id: "builtin-brainstorm",
            name: "Brainstorm",
            prompt: """
                Brainstorming / working session. The product is the idea inventory:

                ## Goal — the problem the session set out to solve.
                ## Idea inventory — EVERY distinct idea raised, one line each, with who proposed \
                it. Do not drop ideas for seeming minor; that defeats the session.
                ## Leading options — the ideas with traction: the case made for them and the \
                concerns raised against them.
                ## Decided / parked — what was chosen, what was explicitly discarded or \
                postponed, and the stated reasons.
                ## Next experiments — concrete validations agreed, each with an owner.
                """,
            isBuiltin: true),
        MeetingTemplate(
            id: "builtin-status",
            name: "Project status",
            prompt: """
                Project status / client check-in:

                ## Status snapshot — overall state in one line (on track / at risk / blocked) \
                only if supported by what was actually said.
                ## Per workstream — progress, changes, and any date that moved (old date → new \
                date).
                ## Risks & issues — each with its severity as discussed and mitigation if one \
                was mentioned.
                ## Scope changes — anything added, cut or renegotiated.
                ## Asks — what each side requested of the other.
                ## Next milestones — confirmed dates and deliverables.
                """,
            isBuiltin: true),
    ]
}
