import Testing

@testable import Granipa

@Suite struct PermissionHealthTests {
    @Test func displayOrderMatchesTheSettingsGrouping() {
        #expect(
            PermissionKind.allCases == [
                .microphone, .systemAudio, .screenRecording, .accessibility, .notifications,
                .calendar,
            ])
        #expect(PermissionKind.allCases.count == 6)
    }

    @Test func attentionCountIsTheNonGrantedTotal() {
        #expect(PermissionHealth(snapshot: .allGranted).attentionCount == 0)

        let mixed = snapshot(
            microphone: .denied,
            systemAudio: .unchecked,
            screenRecording: .granted,
            accessibility: .granted,
            notifications: .notDetermined,
            calendar: .granted)
        let health = PermissionHealth(snapshot: mixed)
        #expect(health.attentionCount == 3)
        #expect(health.totalCount == 6)
        #expect(health.detail.contains("3 of 6"))
        #expect(!health.detail.contains("2 of 6"))
    }

    @Test func sixUncheckedNeedSixAttentions() {
        let health = PermissionHealth(snapshot: PermissionSnapshot())
        #expect(health.attentionCount == 6)
        #expect(health.detail.contains("6 of 6"))
    }

    @Test func firstActionableFollowsDisplayOrder() {
        #expect(PermissionHealth(snapshot: .allGranted).firstActionable == nil)

        let screenFirst = snapshot(
            microphone: .granted,
            systemAudio: .granted,
            screenRecording: .denied)
        #expect(PermissionHealth(snapshot: screenFirst).firstActionable == .screenRecording)

        let systemFirst = snapshot(
            microphone: .granted,
            systemAudio: .unchecked,
            calendar: .denied)
        #expect(PermissionHealth(snapshot: systemFirst).firstActionable == .systemAudio)
    }

    @Test func fixRecommendedHidesWhenRefreshingOrAllGranted() {
        #expect(!PermissionHealth(snapshot: .allGranted).showsFixRecommended)
        #expect(
            !PermissionHealth(
                snapshot: snapshot(microphone: .denied, isRefreshing: true)
            ).showsFixRecommended)
        #expect(
            PermissionHealth(snapshot: snapshot(microphone: .denied)).showsFixRecommended)
    }

    @Test func refreshingHeadlineDoesNotInventAScanClock() {
        let health = PermissionHealth(snapshot: snapshot(isRefreshing: true))
        #expect(health.headline == "Checking permissions")
        #expect(!health.detail.contains("9:41"))
        #expect(!health.detail.lowercased().contains("last scanned"))
    }

    @Test func rowActionsPreserveRequestCheckAndOpenSettings() {
        let health = PermissionHealth(
            snapshot: snapshot(
                microphone: .notDetermined,
                systemAudio: .unchecked,
                screenRecording: .denied,
                accessibility: .denied,
                notifications: .notDetermined,
                calendar: .granted))

        #expect(action(health, .microphone) == .request)
        #expect(action(health, .systemAudio) == .checkSystemAudio)
        #expect(action(health, .screenRecording) == .openSettings)
        #expect(action(health, .accessibility) == .openSettings)
        #expect(action(health, .notifications) == .request)
        #expect(action(health, .calendar) == .none)
    }

    @Test func systemAudioKeepsAnExplicitCheckAndDoesNotRequest() {
        #expect(
            action(PermissionHealth(snapshot: snapshot(systemAudio: .unchecked)), .systemAudio)
                == .checkSystemAudio)
        #expect(
            action(PermissionHealth(snapshot: snapshot(systemAudio: .granted)), .systemAudio)
                == .checkSystemAudio)
        #expect(
            action(PermissionHealth(snapshot: snapshot(systemAudio: .denied)), .systemAudio)
                == .openSettings)
        #expect(
            action(
                PermissionHealth(
                    snapshot: snapshot(systemAudio: .unchecked, probingSystemAudio: true)),
                .systemAudio) == .none)
        #expect(
            PermissionHealth(snapshot: snapshot(systemAudio: .unchecked))
                .rows.first { $0.kind == .systemAudio }?.actionTitle == "Check")
        #expect(
            PermissionHealth(snapshot: snapshot(systemAudio: .granted))
                .rows.first { $0.kind == .systemAudio }?.actionTitle == "Check again")
    }

    @Test func refreshingSuppressesRowActions() {
        let health = PermissionHealth(
            snapshot: snapshot(
                microphone: .notDetermined,
                systemAudio: .unchecked,
                screenRecording: .denied,
                isRefreshing: true))
        for row in health.rows {
            #expect(row.action == .none)
        }
    }

    @Test func statusLabelsCoverEveryPermissionState() {
        let health = PermissionHealth(
            snapshot: snapshot(
                microphone: .granted,
                systemAudio: .unchecked,
                screenRecording: .denied,
                notifications: .notDetermined))
        #expect(label(health, .microphone) == "Granted")
        #expect(label(health, .systemAudio) == "Unchecked")
        #expect(label(health, .screenRecording) == "Denied")
        #expect(label(health, .notifications) == "Not asked")
    }

    @Test func tonesDoNotInventASeventhStatusColor() {
        let health = PermissionHealth(snapshot: .allGranted)
        #expect(health.tone(for: .granted) == .granted)
        #expect(health.tone(for: .denied) == .actionNeeded)
        #expect(health.tone(for: .unchecked) == .actionNeeded)
        #expect(health.tone(for: .notDetermined) == .unknown)
    }

    @Test func paneURLsStayOnTheCurrentSystemSettingsDestinations() {
        #expect(
            PermissionKind.microphone.settingsPane
                == "\(PermissionCenter.securityPane)?Privacy_Microphone")
        #expect(
            PermissionKind.systemAudio.settingsPane
                == "\(PermissionCenter.securityPane)?Privacy_ScreenCapture")
        #expect(
            PermissionKind.screenRecording.settingsPane
                == "\(PermissionCenter.securityPane)?Privacy_ScreenCapture")
        #expect(
            PermissionKind.calendar.settingsPane
                == "\(PermissionCenter.securityPane)?Privacy_Calendars")
        #expect(
            PermissionKind.accessibility.settingsPane
                == "\(PermissionCenter.securityPane)?Privacy_Accessibility")
        #expect(
            PermissionKind.notifications.settingsPane
                == "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    }

    @Test func onlyMicCalendarAndNotificationsCanRequest() {
        #expect(PermissionKind.microphone.canRequest)
        #expect(PermissionKind.calendar.canRequest)
        #expect(PermissionKind.notifications.canRequest)
        #expect(!PermissionKind.systemAudio.canRequest)
        #expect(!PermissionKind.screenRecording.canRequest)
        #expect(!PermissionKind.accessibility.canRequest)
    }
}

private func snapshot(
    microphone: PermissionState = .granted,
    systemAudio: PermissionState = .granted,
    screenRecording: PermissionState = .granted,
    accessibility: PermissionState = .granted,
    notifications: PermissionState = .granted,
    calendar: PermissionState = .granted,
    probingSystemAudio: Bool = false,
    isRefreshing: Bool = false
) -> PermissionSnapshot {
    PermissionSnapshot(
        microphone: microphone,
        systemAudio: systemAudio,
        screenRecording: screenRecording,
        accessibility: accessibility,
        notifications: notifications,
        calendar: calendar,
        probingSystemAudio: probingSystemAudio,
        isRefreshing: isRefreshing)
}

extension PermissionSnapshot {
    fileprivate static var allGranted: PermissionSnapshot { snapshot() }
}

private func action(_ health: PermissionHealth, _ kind: PermissionKind) -> PermissionRowAction {
    health.rows.first { $0.kind == kind }?.action ?? .none
}

private func label(_ health: PermissionHealth, _ kind: PermissionKind) -> String {
    health.rows.first { $0.kind == kind }?.statusLabel ?? ""
}
