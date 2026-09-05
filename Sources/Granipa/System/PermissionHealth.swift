import Foundation

extension PermissionState: Equatable {}

enum PermissionKind: String, CaseIterable, Equatable, Identifiable, Sendable {
    case microphone
    case systemAudio
    case screenRecording
    case accessibility
    case notifications
    case calendar

    var id: String { rawValue }

    var title: String {
        switch self {
        case .microphone: "Microphone"
        case .systemAudio: "System Audio Recording"
        case .screenRecording: "Screen Recording"
        case .accessibility: "Accessibility"
        case .notifications: "Notifications"
        case .calendar: "Calendars"
        }
    }

    var summary: String {
        switch self {
        case .microphone:
            "Your side of the conversation."
        case .systemAudio:
            "Captures meeting sound from other participants."
        case .screenRecording:
            "Captures text for OCR."
        case .accessibility:
            "Auto-paste from clipboard history and window snapping."
        case .notifications:
            "Meeting alerts and transcription status."
        case .calendar:
            "Shows upcoming meetings and auto-titles recordings."
        }
    }

    var systemImage: String {
        switch self {
        case .microphone: "mic.fill"
        case .systemAudio: "speaker.wave.2.fill"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .accessibility: "accessibility"
        case .notifications: "bell.badge.fill"
        case .calendar: "calendar"
        }
    }

    var canRequest: Bool {
        switch self {
        case .microphone, .calendar, .notifications: true
        case .systemAudio, .screenRecording, .accessibility: false
        }
    }

    var settingsPane: String {
        switch self {
        case .microphone:
            "\(PermissionCenter.securityPane)?Privacy_Microphone"
        case .systemAudio, .screenRecording:
            "\(PermissionCenter.securityPane)?Privacy_ScreenCapture"
        case .calendar:
            "\(PermissionCenter.securityPane)?Privacy_Calendars"
        case .notifications:
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        case .accessibility:
            "\(PermissionCenter.securityPane)?Privacy_Accessibility"
        }
    }
}

enum PermissionTone: Equatable, Sendable {
    case granted
    case actionNeeded
    case unknown
}

enum PermissionRowAction: Equatable, Sendable {
    case none
    case request
    case openSettings
    case checkSystemAudio
}

struct PermissionSnapshot: Equatable, Sendable {
    var microphone: PermissionState = .unchecked
    var systemAudio: PermissionState = .unchecked
    var screenRecording: PermissionState = .unchecked
    var accessibility: PermissionState = .unchecked
    var notifications: PermissionState = .unchecked
    var calendar: PermissionState = .unchecked
    var probingSystemAudio = false
    var isRefreshing = false

    func state(for kind: PermissionKind) -> PermissionState {
        switch kind {
        case .microphone: microphone
        case .systemAudio: systemAudio
        case .screenRecording: screenRecording
        case .accessibility: accessibility
        case .notifications: notifications
        case .calendar: calendar
        }
    }

    @MainActor
    init(center: PermissionCenter, isRefreshing: Bool) {
        self.init(
            microphone: center.microphone,
            systemAudio: center.systemAudio,
            screenRecording: center.screenRecording,
            accessibility: center.accessibility,
            notifications: center.notifications,
            calendar: center.calendar,
            probingSystemAudio: center.probingSystemAudio,
            isRefreshing: isRefreshing)
    }

    init(
        microphone: PermissionState = .unchecked,
        systemAudio: PermissionState = .unchecked,
        screenRecording: PermissionState = .unchecked,
        accessibility: PermissionState = .unchecked,
        notifications: PermissionState = .unchecked,
        calendar: PermissionState = .unchecked,
        probingSystemAudio: Bool = false,
        isRefreshing: Bool = false
    ) {
        self.microphone = microphone
        self.systemAudio = systemAudio
        self.screenRecording = screenRecording
        self.accessibility = accessibility
        self.notifications = notifications
        self.calendar = calendar
        self.probingSystemAudio = probingSystemAudio
        self.isRefreshing = isRefreshing
    }
}

struct PermissionRowModel: Equatable, Identifiable, Sendable {
    var id: PermissionKind { kind }
    var kind: PermissionKind
    var state: PermissionState
    var tone: PermissionTone
    var statusLabel: String
    var action: PermissionRowAction
    var actionTitle: String?
    var probing: Bool
}

struct PermissionHealth: Equatable, Sendable {
    var snapshot: PermissionSnapshot

    var totalCount: Int { PermissionKind.allCases.count }

    var attentionCount: Int {
        PermissionKind.allCases.reduce(0) { count, kind in
            snapshot.state(for: kind) == .granted ? count : count + 1
        }
    }

    var firstActionable: PermissionKind? {
        PermissionKind.allCases.first { snapshot.state(for: $0) != .granted }
    }

    var showsFixRecommended: Bool {
        !snapshot.isRefreshing && firstActionable != nil
    }

    var headline: String {
        if snapshot.isRefreshing { return "Checking permissions" }
        return attentionCount == 0 ? "All granted" : "Action needed"
    }

    var detail: String {
        if snapshot.isRefreshing { return "Reading current status from macOS." }
        if attentionCount == 0 { return "All 6 permissions are granted." }
        return "\(attentionCount) of \(totalCount) permissions need attention"
    }

    var rows: [PermissionRowModel] {
        PermissionKind.allCases.map { kind in
            let state = snapshot.state(for: kind)
            let action = self.action(for: kind)
            return PermissionRowModel(
                kind: kind,
                state: state,
                tone: tone(for: state),
                statusLabel: statusLabel(for: state),
                action: action,
                actionTitle: title(for: action, kind: kind),
                probing: kind == .systemAudio && snapshot.probingSystemAudio)
        }
    }

    func tone(for state: PermissionState) -> PermissionTone {
        switch state {
        case .granted: .granted
        case .denied, .unchecked: .actionNeeded
        case .notDetermined: .unknown
        }
    }

    func statusLabel(for state: PermissionState) -> String {
        switch state {
        case .granted: "Granted"
        case .denied: "Denied"
        case .notDetermined: "Not asked"
        case .unchecked: "Unchecked"
        }
    }

    func action(for kind: PermissionKind) -> PermissionRowAction {
        if snapshot.isRefreshing { return .none }
        if kind == .systemAudio, snapshot.probingSystemAudio { return .none }
        let state = snapshot.state(for: kind)
        if kind == .systemAudio {
            return state == .denied ? .openSettings : .checkSystemAudio
        }
        switch state {
        case .notDetermined where kind.canRequest: return .request
        case .denied: return .openSettings
        default: return .none
        }
    }

    private func title(for action: PermissionRowAction, kind: PermissionKind) -> String? {
        switch action {
        case .none: nil
        case .request: "Request"
        case .openSettings: "Open Settings"
        case .checkSystemAudio:
            snapshot.state(for: kind) == .granted ? "Check again" : "Check"
        }
    }
}
