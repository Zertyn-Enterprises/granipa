import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var windowWidth = ShellLayout.defaultWindowWidth
    @State private var inspectorOverride: Bool?
    @State private var settingsSession = SettingsSession()
    @State private var settingsReturn: AppNavigation.SettingsReturn?

    private var showsSettings: Bool { app.sidebarDestination == .settings }

    private static func looksLikePermissionIssue(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("permission") || lower.contains("denied")
            || lower.contains("not authorized") || lower.contains("privacy")
    }

    /// Fixture launches skip the welcome window in-process. They must not
    /// write `onboardingCompleted` — cfprefsd ignores CFFIXED_USER_HOME.
    nonisolated static func shouldPresentOnboarding(completed: Bool, fixtureActive: Bool) -> Bool {
        !fixtureActive && !completed
    }

    private var inspectorKind: InspectorContentKind {
        AppNavigation.inspectorKind(
            destination: app.sidebarDestination,
            dictationShowsInspector: AppNavigation.dictationShowsInspector(app.dictation.phase),
            windowWidth: windowWidth,
            meetingSelected: app.sidebarDestination != .dictation && app.selectedMeeting != nil)
    }

    private var inspectorPresentation: InspectorPresentation {
        ShellLayout.presentation(
            windowWidth: windowWidth,
            userExpanded: inspectorOverride,
            kind: inspectorKind)
    }

    private var inspectorToggleHelp: String {
        if !AppNavigation.inspectorToggleEnabled(kind: inspectorKind) {
            return "Inspector unavailable"
        }
        return inspectorPresentation == .hidden ? "Show inspector" : "Hide inspector"
    }

    var body: some View {
        HStack(spacing: 0) {
            if showsSettings {
                SettingsSidebar(
                    selection: settingsSession.section,
                    isRecording: app.recorder.isRecording,
                    select: { settingsSession.section = $0 },
                    onBack: leaveEmbeddedSettings)
                    .frame(width: ShellLayout.sidebarWidth)
            } else {
                SidebarView()
                    .frame(width: ShellLayout.sidebarWidth)
                    .background(Theme.bgSidebar)
            }

            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)

            if showsSettings {
                SettingsView(session: $settingsSession)
            } else {
                contentColumn
            }

            if inspectorPresentation == .column {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1)
                InspectorPane(kind: inspectorKind)
                    .frame(width: ShellLayout.inspectorColumnWidth)
            }
        }
        .overlay(alignment: .trailing) {
            if inspectorPresentation == .overlay {
                InspectorPane(kind: inspectorKind)
                    .frame(minWidth: ShellLayout.inspectorOverlayMinWidth)
                    .frame(width: ShellLayout.inspectorColumnWidth)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.border).frame(width: 1)
                    }
            }
        }
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .frame(
            minWidth: ShellLayout.minWidth,
            idealWidth: ShellLayout.defaultWindowWidth,
            minHeight: ShellLayout.minHeight,
            idealHeight: ShellLayout.defaultWindowHeight)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: MainWindowWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(MainWindowWidthKey.self) { windowWidth = $0 }
        .background {
            Button("Settings…") { openEmbeddedSettings() }
                .keyboardShortcut(",", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .onChange(of: app.sidebarDestination) { old, new in
            if new == .settings,
                let snap = AppNavigation.SettingsReturn.snapshot(
                    destination: old,
                    selectedMeetingID: app.selectedMeetingID,
                    selectedFolderID: app.selectedFolderID,
                    libraryFilter: AppNavigation.activeLibraryFilter(
                        destination: old, stored: app.homeLibraryFilter))
            {
                settingsReturn = snap
            }
        }
        .toolbar {
            if AppNavigation.showsInspectorToggle(destination: app.sidebarDestination) {
                Button {
                    inspectorOverride = inspectorPresentation == .hidden
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .disabled(!AppNavigation.inspectorToggleEnabled(kind: inspectorKind))
                .help(inspectorToggleHelp)
                .accessibilityLabel(inspectorToggleHelp)
            }
        }
        .onChange(of: app.recorder.isRecording) {
            if app.recorder.isRecording {
                CaptionsOverlayController.shared.resetDismissed()
                openWindow(id: "recording-hud")
            }
        }
        .onChange(of: app.processingMeetingID) {
            if app.processingMeetingID == nil, !app.recorder.isRecording {
                dismissWindow(id: "recording-hud")
            } else if app.processingMeetingID != nil {
                openWindow(id: "recording-hud")
            }
        }
        .alert("Error", isPresented: .constant(app.loadError != nil)) {
            if let error = app.loadError, Self.looksLikePermissionIssue(error) {
                Button("Open Settings") {
                    app.loadError = nil
                    openEmbeddedSettings()
                }
            }
            Button("OK") { app.loadError = nil }
        } message: {
            Text(app.loadError ?? "")
        }
        .onAppear {
            #if DEBUG
            let fixtureActive = V2FixtureRuntime.isActive
            #else
            let fixtureActive = false
            #endif
            if Self.shouldPresentOnboarding(
                completed: onboardingCompleted, fixtureActive: fixtureActive)
            {
                openWindow(id: "onboarding")
            }
        }
    }

    private var contentColumn: some View {
        VStack(spacing: 0) {
            if let appName = app.detector.detectedApp, !app.recorder.isRecording {
                detectionBanner(appName: appName)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .move(edge: .top).combined(with: .opacity)
                    )
                    .animation(
                        reduceMotion ? nil : .easeOut(duration: Theme.motionNormal),
                        value: appName)
            }
            Group {
                if app.sidebarDestination == .dictation {
                    DictationHistoryView()
                } else if let meeting = app.selectedMeeting {
                    MeetingDetailView(
                        meeting: meeting,
                        preferNotes: AppNavigation.activeLibraryFilter(
                            destination: app.sidebarDestination,
                            stored: app.homeLibraryFilter) == .notes
                    )
                    .id(meeting.id)
                } else {
                    switch app.sidebarDestination {
                    case .home, .meetings, .notes, .files:
                        HomeView()
                    case .dictation:
                        DictationHistoryView()
                    case .settings:
                        EmptyView()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Theme.bg)
    }

    private func detectionBanner(appName: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "video.fill")
                .foregroundStyle(Theme.accent)
            Text("Looks like \(appName) is in a call.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Record") {
                app.startRecordingFromDetection()
            }
            .granipaPrimaryControl()
            Button("Dismiss") {
                app.detector.dismiss()
            }
            .granipaSecondaryControl()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Theme.accent.opacity(0.08))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }

    private func openEmbeddedSettings() {
        app.sidebarDestination = .settings
    }

    private func leaveEmbeddedSettings() {
        let restored = AppNavigation.leaveSettings(settingsReturn)
        app.sidebarDestination = restored.destination
        app.selectedMeetingID = restored.selectedMeetingID
        app.selectedFolderID = restored.selectedFolderID
        app.homeLibraryFilter = restored.libraryFilter
    }
}

private struct MainWindowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = ShellLayout.defaultWindowWidth
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
