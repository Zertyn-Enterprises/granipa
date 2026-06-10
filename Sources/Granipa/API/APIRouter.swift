import Foundation

struct MeetingSummaryDTO: Encodable {
    let id: String
    let title: String
    let createdAt: Date
    let startedAt: Date?
    let endedAt: Date?
    let language: String
    let status: String

    init(_ meeting: Meeting) {
        id = meeting.id
        title = meeting.title
        createdAt = meeting.createdAt
        startedAt = meeting.startedAt
        endedAt = meeting.endedAt
        language = meeting.language
        status = meeting.status.rawValue
    }
}

struct MeetingDetailDTO: Encodable {
    let id: String
    let title: String
    let createdAt: Date
    let startedAt: Date?
    let endedAt: Date?
    let language: String
    let status: String
    let notesMarkdown: String
    let enhancedNotesMarkdown: String?
    let summary: String?
    let actionItems: [ActionItem]
    let emailDraft: String?

    init(_ meeting: Meeting) {
        id = meeting.id
        title = meeting.title
        createdAt = meeting.createdAt
        startedAt = meeting.startedAt
        endedAt = meeting.endedAt
        language = meeting.language
        status = meeting.status.rawValue
        notesMarkdown = meeting.notesMarkdown
        enhancedNotesMarkdown = meeting.enhancedNotesMarkdown
        summary = meeting.summary
        actionItems = ActionItem.decodeList(from: meeting.actionItemsJSON)
        emailDraft = meeting.emailDraft
    }
}

struct SegmentDTO: Encodable {
    let speaker: String
    let channel: String
    let text: String
    let startSeconds: Double
    let endSeconds: Double

    init(_ segment: TranscriptSegment) {
        speaker = segment.speaker
        channel = segment.channel.rawValue
        text = segment.text
        startSeconds = segment.startSeconds
        endSeconds = segment.endSeconds
    }
}

enum APIRouter {
    static func route(
        _ request: HTTPRequest,
        token: String,
        database: AppDatabase,
        enhanceTrigger: @escaping @Sendable (String) -> Void
    ) -> HTTPResponse {
        if request.path == "/v1/health" {
            return .json(200, ["status": "ok"])
        }

        let authorized = request.headers["authorization"] == "Bearer \(token)"
        guard authorized else {
            return .error(401, "Missing or invalid bearer token.")
        }

        let parts = request.path.split(separator: "/").map(String.init)
        // Expected shapes: ["v1", "meetings"], ["v1", "meetings", id, sub?]
        guard parts.first == "v1", parts.count >= 2, parts[1] == "meetings" else {
            return .error(404, "Unknown route.")
        }

        do {
            switch (request.method, parts.count) {
            case ("GET", 2):
                let limit = request.query["limit"].flatMap(Int.init) ?? 50
                let meetings = try database.fetchMeetings()
                return .json(200, meetings.prefix(max(0, limit)).map(MeetingSummaryDTO.init))

            case ("GET", 3):
                guard let meeting = try database.fetchMeeting(id: parts[2]) else {
                    return .error(404, "Meeting not found.")
                }
                return .json(200, MeetingDetailDTO(meeting))

            case ("GET", 4) where parts[3] == "transcript":
                guard let meeting = try database.fetchMeeting(id: parts[2]) else {
                    return .error(404, "Meeting not found.")
                }
                let segments = try database.fetchSegments(meetingID: meeting.id, finalOnly: true)
                return .json(200, segments.map(SegmentDTO.init))

            case ("GET", 4) where parts[3] == "notes":
                guard let meeting = try database.fetchMeeting(id: parts[2]) else {
                    return .error(404, "Meeting not found.")
                }
                return .json(200, MeetingDetailDTO(meeting))

            case ("POST", 4) where parts[3] == "enhance":
                guard let meeting = try database.fetchMeeting(id: parts[2]) else {
                    return .error(404, "Meeting not found.")
                }
                enhanceTrigger(meeting.id)
                return .json(202, ["status": "enhancing", "meetingId": meeting.id])

            case ("GET", _), ("POST", _):
                return .error(404, "Unknown route.")

            default:
                return .error(405, "Method not allowed.")
            }
        } catch {
            return .error(500, "Internal error.")
        }
    }
}
