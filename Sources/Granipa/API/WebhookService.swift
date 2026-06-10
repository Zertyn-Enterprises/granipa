import CryptoKit
import Foundation

enum WebhookService {
    static let maxAttempts = 5

    static func signature(payload: Data, secret: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return "sha256=" + mac.map { String(format: "%02x", $0) }.joined()
    }

    static func backoff(attempts: Int) -> TimeInterval {
        30 * pow(4, Double(attempts - 1))
    }

    static func enqueue(event: WebhookEvent, payload: some Encodable, database: AppDatabase) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? database.enqueueDeliveries(event: event, payload: String(decoding: data, as: UTF8.self))
    }

    static func deliverDue(database: AppDatabase) async {
        guard let due = try? database.dueDeliveries() else { return }
        for (delivery, webhook) in due {
            var updated = delivery
            updated.attempts += 1
            let success = await send(delivery: delivery, webhook: webhook)
            if success {
                updated.status = "delivered"
            } else if updated.attempts >= maxAttempts {
                updated.status = "failed"
            } else {
                updated.nextAttemptAt = Date(timeIntervalSinceNow: backoff(attempts: updated.attempts))
            }
            try? database.updateDelivery(updated)
        }
    }

    private static func send(delivery: WebhookDelivery, webhook: Webhook) async -> Bool {
        guard let url = URL(string: webhook.url), url.scheme?.hasPrefix("http") == true else {
            return false
        }
        let body = Data(delivery.payload.utf8)
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(delivery.event, forHTTPHeaderField: "X-Granipa-Event")
        request.setValue(delivery.id, forHTTPHeaderField: "X-Granipa-Delivery")
        request.setValue(
            signature(payload: body, secret: webhook.secret),
            forHTTPHeaderField: "X-Granipa-Signature")

        guard let (_, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse
        else {
            return false
        }
        return (200..<300).contains(http.statusCode)
    }
}

struct MeetingStartedPayload: Encodable {
    let event = "meeting.started"
    let timestamp: Date
    let meeting: MeetingSummaryDTO
}

struct MeetingCompletedPayload: Encodable {
    let event = "meeting.completed"
    let timestamp: Date
    let meeting: MeetingDetailDTO
    let transcript: [SegmentDTO]
}

struct NotesEnhancedPayload: Encodable {
    let event = "notes.enhanced"
    let timestamp: Date
    let meeting: MeetingDetailDTO
}
