import Foundation
import GRDB

enum WebhookEvent: String, Codable, CaseIterable, Sendable {
    case meetingStarted = "meeting.started"
    case meetingCompleted = "meeting.completed"
    case notesEnhanced = "notes.enhanced"
}

struct Webhook: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var id: String
    var url: String
    var secret: String
    var events: String
    var enabled: Bool

    var eventList: [WebhookEvent] {
        events.split(separator: ",").compactMap { WebhookEvent(rawValue: String($0)) }
    }

    func subscribes(to event: WebhookEvent) -> Bool {
        eventList.contains(event)
    }

    static func new() -> Webhook {
        Webhook(
            id: UUID().uuidString,
            url: "",
            secret: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
            events: WebhookEvent.allCases.map(\.rawValue).joined(separator: ","),
            enabled: true)
    }
}

struct WebhookDelivery: Codable, Identifiable, Hashable, Sendable, FetchableRecord, PersistableRecord {
    var id: String
    var webhookID: String
    var event: String
    var payload: String
    var attempts: Int
    var nextAttemptAt: Date
    var status: String

    static func new(webhookID: String, event: WebhookEvent, payload: String) -> WebhookDelivery {
        WebhookDelivery(
            id: UUID().uuidString,
            webhookID: webhookID,
            event: event.rawValue,
            payload: payload,
            attempts: 0,
            nextAttemptAt: .now,
            status: "pending")
    }
}
