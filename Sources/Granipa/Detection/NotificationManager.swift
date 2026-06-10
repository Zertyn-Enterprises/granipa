import Foundation
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let shared = NotificationManager()
    static let recordAction = "RECORD_MEETING"
    static let category = "MEETING_DETECTED"

    // UNUserNotificationCenter crashes outside a real .app bundle (e.g. swift run).
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }

    private let onRecord: @Sendable () -> Void

    private override init() {
        onRecord = {
            Task { @MainActor in
                NotificationManager.recordHandler?()
            }
        }
        super.init()
    }

    @MainActor static var recordHandler: (() -> Void)?

    func setup() {
        guard Self.isAvailable else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let record = UNNotificationAction(
            identifier: Self.recordAction, title: "Record", options: [.foreground])
        let category = UNNotificationCategory(
            identifier: Self.category, actions: [record], intentIdentifiers: [])
        center.setNotificationCategories([category])
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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == Self.recordAction
            || response.actionIdentifier == UNNotificationDefaultActionIdentifier
        {
            onRecord()
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
