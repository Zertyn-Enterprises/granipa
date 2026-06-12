import AVFoundation
import AppKit
import EventKit
import UserNotifications

enum PermissionState: Sendable {
    case granted
    case denied
    case notDetermined
    case unchecked
}

@MainActor
@Observable
final class PermissionCenter {
    private(set) var microphone: PermissionState = .unchecked
    private(set) var systemAudio: PermissionState = .unchecked
    private(set) var calendar: PermissionState = .unchecked
    private(set) var notifications: PermissionState = .unchecked
    private(set) var accessibility: PermissionState = .unchecked
    private(set) var screenRecording: PermissionState = .unchecked
    private(set) var probingSystemAudio = false

    static let securityPane = "x-apple.systempreferences:com.apple.preference.security"

    func refresh() async {
        microphone =
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: .granted
            case .denied, .restricted: .denied
            default: .notDetermined
            }
        calendar =
            switch EKEventStore.authorizationStatus(for: .event) {
            case .fullAccess: .granted
            case .denied, .restricted, .writeOnly: .denied
            default: .notDetermined
            }
        accessibility = AXIsProcessTrusted() ? .granted : .denied
        screenRecording = CGPreflightScreenCaptureAccess() ? .granted : .denied
        if NotificationManager.isAvailable {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notifications =
                switch settings.authorizationStatus {
                case .authorized, .provisional: .granted
                case .denied: .denied
                default: .notDetermined
                }
        }
    }

    // There is no public preflight for the system-audio TCC grant, so the only
    // truthful check is creating (and immediately tearing down) a real tap —
    // the same call a recording makes. First run triggers the system prompt,
    // which is why this only runs from an explicit button.
    func probeSystemAudio() async {
        probingSystemAudio = true
        defer { probingSystemAudio = false }
        let result = await Task.detached { () -> PermissionState in
            let tap = SystemAudioTap()
            do {
                try tap.start { _, _ in }
                tap.stop()
                return .granted
            } catch {
                return .denied
            }
        }.value
        systemAudio = result
    }
}
