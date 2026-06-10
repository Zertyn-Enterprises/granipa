import Foundation
import GRDB
import Testing

@testable import Granipa

@Suite struct HTTPMessageTests {
    @Test func parsesRequestLineHeadersAndQuery() throws {
        let raw = "GET /v1/meetings?limit=5&q=hola%20mundo HTTP/1.1\r\nHost: localhost\r\nAuthorization: Bearer abc\r\n\r\n"
        let request = try #require(HTTPRequest.parse(Data(raw.utf8)))
        #expect(request.method == "GET")
        #expect(request.path == "/v1/meetings")
        #expect(request.query == ["limit": "5", "q": "hola mundo"])
        #expect(request.headers["authorization"] == "Bearer abc")
    }

    @Test func parsesBody() throws {
        let raw = "POST /x HTTP/1.1\r\nContent-Length: 4\r\n\r\nbody"
        let request = try #require(HTTPRequest.parse(Data(raw.utf8)))
        #expect(String(decoding: request.body, as: UTF8.self) == "body")
        #expect(HTTPRequest.contentLength(fromHeaderData: Data(raw.utf8)) == 4)
    }

    @Test func serializesResponse() {
        let response = HTTPResponse.json(200, ["ok": true])
        let text = String(decoding: response.serialize(), as: UTF8.self)
        #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
        #expect(text.contains("Content-Type: application/json"))
        #expect(text.hasSuffix("{\"ok\":true}"))
    }
}

@Suite struct APIRouterTests {
    private func makeDatabase() throws -> AppDatabase {
        try AppDatabase(writer: DatabaseQueue())
    }

    private func get(_ path: String, token: String = "tok") -> HTTPRequest {
        HTTPRequest(
            method: "GET", path: path, query: [:],
            headers: ["authorization": "Bearer \(token)"], body: Data())
    }

    @Test func healthNeedsNoAuth() throws {
        let db = try makeDatabase()
        let response = APIRouter.route(
            HTTPRequest(method: "GET", path: "/v1/health", query: [:], headers: [:], body: Data()),
            token: "tok", database: db, enhanceTrigger: { _ in })
        #expect(response.status == 200)
    }

    @Test func rejectsBadToken() throws {
        let db = try makeDatabase()
        let response = APIRouter.route(
            get("/v1/meetings", token: "wrong"), token: "tok", database: db, enhanceTrigger: { _ in })
        #expect(response.status == 401)
    }

    @Test func listsAndFetchesMeetings() throws {
        let db = try makeDatabase()
        var meeting = Meeting.new(title: "API test", language: "en-US")
        meeting.summary = "S"
        try db.save(meeting)
        try db.save(
            TranscriptSegment.new(
                meetingID: meeting.id, channel: .mic, speaker: "Me",
                text: "hello", startSeconds: 0, endSeconds: 1, isFinal: true))

        let list = APIRouter.route(
            get("/v1/meetings"), token: "tok", database: db, enhanceTrigger: { _ in })
        #expect(list.status == 200)
        #expect(String(decoding: list.body, as: UTF8.self).contains("API test"))

        let detail = APIRouter.route(
            get("/v1/meetings/\(meeting.id)"), token: "tok", database: db, enhanceTrigger: { _ in })
        #expect(detail.status == 200)
        #expect(String(decoding: detail.body, as: UTF8.self).contains("\"summary\":\"S\""))

        let transcript = APIRouter.route(
            get("/v1/meetings/\(meeting.id)/transcript"), token: "tok", database: db,
            enhanceTrigger: { _ in })
        #expect(transcript.status == 200)
        #expect(String(decoding: transcript.body, as: UTF8.self).contains("\"text\":\"hello\""))

        let missing = APIRouter.route(
            get("/v1/meetings/nope"), token: "tok", database: db, enhanceTrigger: { _ in })
        #expect(missing.status == 404)
    }

    @Test func enhanceTriggersCallback() throws {
        let db = try makeDatabase()
        let meeting = Meeting.new(title: "T", language: "en-US")
        try db.save(meeting)

        final class Captured: @unchecked Sendable {
            var id: String?
        }
        let captured = Captured()
        let response = APIRouter.route(
            HTTPRequest(
                method: "POST", path: "/v1/meetings/\(meeting.id)/enhance", query: [:],
                headers: ["authorization": "Bearer tok"], body: Data()),
            token: "tok", database: db, enhanceTrigger: { captured.id = $0 })
        #expect(response.status == 202)
        #expect(captured.id == meeting.id)
    }
}

@Suite struct WebhookTests {
    @Test func signatureIsStableHMAC() {
        let signature = WebhookService.signature(payload: Data("hello".utf8), secret: "secret")
        #expect(signature == "sha256=88aab3ede8d3adf94d26ab90d3bafd4a2083070c3bcce9c014ee04a443847c0b")
    }

    @Test func enqueueMatchesSubscribedWebhooksOnly() throws {
        let db = try AppDatabase(writer: DatabaseQueue())
        var subscribed = Webhook.new()
        subscribed.url = "https://a.example/hook"
        try db.save(subscribed)
        var unsubscribed = Webhook.new()
        unsubscribed.url = "https://b.example/hook"
        unsubscribed.events = WebhookEvent.meetingStarted.rawValue
        try db.save(unsubscribed)
        var disabled = Webhook.new()
        disabled.url = "https://c.example/hook"
        disabled.enabled = false
        try db.save(disabled)

        WebhookService.enqueue(event: .notesEnhanced, payload: ["x": 1], database: db)

        let due = try db.dueDeliveries()
        #expect(due.count == 1)
        #expect(due[0].1.id == subscribed.id)
        #expect(due[0].0.event == "notes.enhanced")
    }

    @Test func backoffGrows() {
        #expect(WebhookService.backoff(attempts: 1) == 30)
        #expect(WebhookService.backoff(attempts: 2) == 120)
        #expect(WebhookService.backoff(attempts: 3) == 480)
    }
}
