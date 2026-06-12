import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationManager()
    static let recordAction = "RECORD_MEETING"
    static let category = "MEETING_DETECTED"
    static let stopAction = "STOP_RECORDING"
    static let endedCategory = "MEETING_ENDED"

    // UNUserNotificationCenter crashes outside a real .app bundle (e.g. swift run).
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    private let onRecord: @Sendable () -> Void
    private let onStop: @Sendable () -> Void

    private override init() {
        onRecord = {
            Task { @MainActor in
                NotificationManager.recordHandler?()
            }
        }
        onStop = {
            Task { @MainActor in
                NotificationManager.stopHandler?()
            }
        }
        super.init()
    }

    @MainActor static var recordHandler: (() -> Void)?
    @MainActor static var stopHandler: (() -> Void)?

    static func authorizationDenied() async -> Bool {
        guard isAvailable else { return false }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return settings.authorizationStatus == .denied
    }

    func setup() {
        guard Self.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let record = UNNotificationAction(
            identifier: Self.recordAction, title: "Record", options: [.foreground])
        let detected = UNNotificationCategory(
            identifier: Self.category, actions: [record], intentIdentifiers: [])
        let stop = UNNotificationAction(
            identifier: Self.stopAction, title: "Stop & process", options: [])
        let ended = UNNotificationCategory(
            identifier: Self.endedCategory, actions: [stop], intentIdentifiers: [])
        center.setNotificationCategories([detected, ended])
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyMeetingDetected(appName: String) {
        guard Self.isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "Meeting detected"
        content.body = "Looks like \(appName) is in a call. Record it?"
        content.categoryIdentifier = Self.category
        let request = UNNotificationRequest(
            identifier: "meeting-detected", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notifyMeetingEnded() {
        guard Self.isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = "Meeting ended?"
        content.body = "The meeting app hung up. Stop recording and process your notes?"
        content.categoryIdentifier = Self.endedCategory
        let request = UNNotificationRequest(
            identifier: "meeting-ended", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func notify(title: String, body: String) {
        guard Self.isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let category = response.notification.request.content.categoryIdentifier
        switch (category, response.actionIdentifier) {
        case (Self.category, Self.recordAction),
            (Self.category, UNNotificationDefaultActionIdentifier):
            onRecord()
        case (Self.endedCategory, Self.stopAction):
            onStop()
        default:
            break
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
