import EventKit
import Foundation
import Observation

struct CalendarMeeting: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let joinURL: URL?

    static func extractJoinURL(from texts: [String?]) -> URL? {
        let pattern =
            #"https://[^\s<>"']*(zoom\.us/j/|meet\.google\.com/|teams\.microsoft\.com/l/|webex\.com/)[^\s<>"']*"#
        for text in texts.compactMap({ $0 }) {
            if let range = text.range(of: pattern, options: .regularExpression) {
                var candidate = String(text[range])
                while let last = candidate.last, ".,;)".contains(last) {
                    candidate.removeLast()
                }
                if let url = URL(string: candidate) {
                    return url
                }
            }
        }
        return nil
    }
}

@MainActor
@Observable
final class CalendarService {
    enum Access {
        case unknown
        case granted
        case denied
    }

    private(set) var access: Access = .unknown
    private(set) var upcoming: [CalendarMeeting] = []
    private let store = EKEventStore()
    private var refreshTask: Task<Void, Never>?

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task {
            await requestAccess()
            while !Task.isCancelled {
                refresh()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    private func requestAccess() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            access = granted ? .granted : .denied
        } catch {
            access = .denied
        }
    }

    func refresh() {
        guard access == .granted else { return }
        let now = Date.now
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-3600),
            end: now.addingTimeInterval(48 * 3600),
            calendars: nil)
        let events = store.events(matching: predicate)
        upcoming = events
            .filter { !$0.isAllDay }
            .sorted { $0.startDate < $1.startDate }
            .prefix(8)
            .map { event in
                CalendarMeeting(
                    id: event.eventIdentifier ?? UUID().uuidString,
                    title: event.title ?? "Untitled event",
                    start: event.startDate,
                    end: event.endDate,
                    joinURL: CalendarMeeting.extractJoinURL(from: [
                        event.url?.absoluteString, event.location, event.notes,
                    ]))
            }
    }

    func currentEvent(at date: Date = .now) -> CalendarMeeting? {
        upcoming.first { meeting in
            meeting.start.addingTimeInterval(-15 * 60) <= date && date <= meeting.end
        }
    }
}
