import CryptoKit
import Foundation

struct FolderInfoDTO: Encodable {
    let id: String
    let name: String
    let team: String?

    init(_ folder: Folder) {
        id = folder.id
        name = folder.name
        team = folder.team
    }
}

struct MeetingSummaryDTO: Encodable {
    let id: String
    let title: String
    let createdAt: Date
    let startedAt: Date?
    let endedAt: Date?
    let language: String
    let status: String
    let folder: FolderInfoDTO?

    init(_ meeting: Meeting, folder: Folder? = nil) {
        id = meeting.id
        title = meeting.title
        createdAt = meeting.createdAt
        startedAt = meeting.startedAt
        endedAt = meeting.endedAt
        language = meeting.language
        status = meeting.status.rawValue
        self.folder = folder.map(FolderInfoDTO.init)
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
    let folder: FolderInfoDTO?

    init(_ meeting: Meeting, folder: Folder? = nil) {
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
        self.folder = folder.map(FolderInfoDTO.init)
    }
}

struct FolderDTO: Encodable {
    let id: String
    let name: String
    let team: String?
    let meetingCount: Int
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

        // Hash-then-compare makes the check constant-time in the token value.
        let authorized = request.headers["authorization"].map { header in
            guard header.hasPrefix("Bearer ") else { return false }
            let provided = String(header.dropFirst("Bearer ".count))
            return SHA256.hash(data: Data(provided.utf8))
                == SHA256.hash(data: Data(token.utf8))
        } ?? false
        guard authorized else {
            return .error(401, "Missing or invalid bearer token.")
        }

        let parts = request.path.split(separator: "/").map(String.init)
        // Expected shapes: ["v1", "meetings"|"folders"], ["v1", "meetings", id, sub?]
        guard parts.first == "v1", parts.count >= 2,
            parts[1] == "meetings" || parts[1] == "folders"
        else {
            return .error(404, "Unknown route.")
        }

        do {
            let foldersByID = Dictionary(
                uniqueKeysWithValues: try database.fetchFolders().map { ($0.id, $0) })

            switch (request.method, parts[1], parts.count) {
            case ("GET", "folders", 2):
                let counts = try database.folderMeetingCounts()
                let folders = foldersByID.values
                    .sorted { ($0.team ?? "", $0.name) < ($1.team ?? "", $1.name) }
                    .map {
                        FolderDTO(
                            id: $0.id, name: $0.name, team: $0.team,
                            meetingCount: counts[$0.id] ?? 0)
                    }
                return .json(200, folders)

            case ("GET", "meetings", 2):
                let limit = request.query["limit"].flatMap(Int.init) ?? 50
                var meetings = try database.fetchMeetings()
                if let folderFilter = request.query["folder"] {
                    meetings = meetings.filter { $0.folderID == folderFilter }
                }
                return .json(
                    200,
                    meetings.prefix(max(0, limit)).map {
                        MeetingSummaryDTO($0, folder: $0.folderID.flatMap { foldersByID[$0] })
                    })

            case ("GET", "meetings", 3):
                guard let meeting = try database.fetchMeeting(id: parts[2]) else {
                    return .error(404, "Meeting not found.")
                }
                return .json(
                    200,
                    MeetingDetailDTO(meeting, folder: meeting.folderID.flatMap { foldersByID[$0] }))

            case ("GET", "meetings", 4) where parts[3] == "transcript":
                guard let meeting = try database.fetchMeeting(id: parts[2]) else {
                    return .error(404, "Meeting not found.")
                }
                let segments = try database.fetchSegments(meetingID: meeting.id, finalOnly: true)
                return .json(200, segments.map(SegmentDTO.init))

            case ("GET", "meetings", 4) where parts[3] == "notes":
                guard let meeting = try database.fetchMeeting(id: parts[2]) else {
                    return .error(404, "Meeting not found.")
                }
                return .json(
                    200,
                    MeetingDetailDTO(meeting, folder: meeting.folderID.flatMap { foldersByID[$0] }))

            case ("POST", "meetings", 4) where parts[3] == "enhance":
                guard let meeting = try database.fetchMeeting(id: parts[2]) else {
                    return .error(404, "Meeting not found.")
                }
                enhanceTrigger(meeting.id)
                return .json(202, ["status": "enhancing", "meetingId": meeting.id])

            case ("GET", _, _), ("POST", _, _):
                return .error(404, "Unknown route.")

            default:
                return .error(405, "Method not allowed.")
            }
        } catch {
            return .error(500, "Internal error.")
        }
    }
}
