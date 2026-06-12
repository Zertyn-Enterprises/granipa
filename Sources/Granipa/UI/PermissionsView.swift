import SwiftUI

struct PermissionsListView: View {
    @State private var center = PermissionCenter()

    var body: some View {
        VStack(spacing: 8) {
            row(
                icon: "mic.fill", name: "Microphone",
                why: "Your side of the conversation.",
                state: center.microphone,
                pane: "\(PermissionCenter.securityPane)?Privacy_Microphone")
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text("System Audio Recording")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("The other participants. Without it, only your mic is captured.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
                if center.probingSystemAudio {
                    ProgressView().controlSize(.small)
                } else if center.systemAudio == .unchecked {
                    Button("Check") { Task { await center.probeSystemAudio() } }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Creates a brief audio tap — macOS asks for the permission if it was never granted.")
                } else {
                    badge(center.systemAudio)
                    if center.systemAudio == .denied {
                        settingsLink("\(PermissionCenter.securityPane)?Privacy_ScreenCapture")
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(cornerRadius: 8)
            row(
                icon: "calendar", name: "Calendars",
                why: "Shows upcoming meetings and auto-titles recordings.",
                state: center.calendar,
                pane: "\(PermissionCenter.securityPane)?Privacy_Calendars")
            row(
                icon: "bell.badge.fill", name: "Notifications",
                why: "\u{201C}Meeting detected — record?\u{201D} prompts.",
                state: center.notifications,
                pane: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
            row(
                icon: "rectangle.dashed.badge.record", name: "Screen Recording",
                why: "Only for text capture (OCR).",
                state: center.screenRecording,
                pane: "\(PermissionCenter.securityPane)?Privacy_ScreenCapture")
            row(
                icon: "accessibility", name: "Accessibility",
                why: "Auto-paste from clipboard history and window snapping.",
                state: center.accessibility,
                pane: "\(PermissionCenter.securityPane)?Privacy_Accessibility")
        }
        .task { await center.refresh() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            Task { await center.refresh() }
        }
    }

    private func row(
        icon: String, name: String, why: String, state: PermissionState, pane: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(why)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            badge(state)
            if state == .denied {
                settingsLink(pane)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 8)
    }

    @ViewBuilder
    private func badge(_ state: PermissionState) -> some View {
        switch state {
        case .granted:
            Label("Granted", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .labelStyle(.titleAndIcon)
        case .denied:
            Label("Denied", systemImage: "xmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.red)
                .labelStyle(.titleAndIcon)
        case .notDetermined:
            Label("Not asked yet", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundStyle(.orange)
                .labelStyle(.titleAndIcon)
        case .unchecked:
            EmptyView()
        }
    }

    private func settingsLink(_ pane: String) -> some View {
        Button("Open Settings") {
            if let url = URL(string: pane) {
                NSWorkspace.shared.open(url)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

struct PermissionsSettings: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("Permissions") {
                PermissionsListView()
                Text("Statuses refresh automatically when you come back from System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Button("Show welcome tour again…") {
                    openWindow(id: "onboarding")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
        }
        .formStyle(.grouped)
    }
}
