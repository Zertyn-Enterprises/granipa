import SwiftUI

struct MainWindow: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openSettings) private var openSettings
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var windowWidth = ShellLayout.defaultWindowWidth
    @State private var inspectorOverride: Bool?

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
            hasContent: inspectorKind != .none)
    }

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: ShellLayout.sidebarWidth)
                .background(Theme.bgSidebar)

            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)

            contentColumn

            if inspectorPresentation == .column {
                Rectangle()
                    .fill(Theme.border)
                    .frame(width: 1)
                InspectorPane(kind: inspectorKind)
                    .frame(width: ShellLayout.inspectorColumnWidth)
                    .transition(.opacity)
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
                    .transition(.opacity)
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: Theme.motionNormal),
            value: inspectorPresentation)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .frame(
            minWidth: ShellLayout.minWidth,
            idealWidth: ShellLayout.defaultWindowWidth,
            minHeight: ShellLayout.minHeight,
            idealHeight: ShellLayout.defaultWindowHeight)
        .environment(\.granipaWindowWidth, windowWidth)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: MainWindowWidthKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(MainWindowWidthKey.self) { windowWidth = $0 }
        .toolbar {
            if inspectorKind != .none {
                Button {
                    inspectorOverride = inspectorPresentation == .hidden
                } label: {
                    Image(systemName: "sidebar.trailing")
                }
                .help(
                    inspectorPresentation == .hidden ? "Show inspector" : "Hide inspector")
                .accessibilityLabel(
                    inspectorPresentation == .hidden ? "Show inspector" : "Hide inspector")
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
                    openSettings()
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
                            : .move(edge: .top).combined(with: .opacity))
            }
            Group {
                if app.sidebarDestination == .dictation {
                    DictationHistoryView()
                } else if let meeting = app.selectedMeeting {
                    MeetingDetailView(
                        meeting: meeting,
                        preferNotes: app.sidebarDestination == .notes
                    )
                    .id(meeting.id)
                } else {
                    switch app.sidebarDestination {
                    case .home:
                        HomeView(mode: app.selectedFolderID == nil ? .inbox : .library)
                    case .meetings:
                        HomeView(mode: .library)
                    case .notes:
                        NotesLibraryView()
                    case .files:
                        FilesLibraryView()
                    case .dictation:
                        DictationHistoryView()
                    }
                }
            }
        }
        .animation(
            reduceMotion ? nil : .easeOut(duration: Theme.motionNormal),
            value: app.detector.detectedApp)
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
}

private struct MainWindowWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = ShellLayout.defaultWindowWidth
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
