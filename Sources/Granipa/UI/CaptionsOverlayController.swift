import AppKit
import SwiftUI

@MainActor
final class CaptionsOverlayController {
    static let shared = CaptionsOverlayController()
    // Fixed bounding box sized for the worst case (header + 2-line warning +
    // two 2-line caption rows + padding ≈ 173 pt). The card sizes to its
    // content and stays pinned to the top; the panel never resizes, so no
    // fittingSize layout pass runs while captions update.
    private static let panelSize = NSSize(width: 656, height: 176)
    private var panel: NSPanel?
    private weak var appState: AppState?
    private(set) var dismissedThisRecording = false

    func attach(appState: AppState) {
        self.appState = appState
        if panel != nil { return }
        let host = NSHostingView(
            rootView: AnyView(CaptionsOverlayView().environment(appState)))

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: Self.panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        self.panel = panel
    }

    func resetDismissed() {
        dismissedThisRecording = false
    }

    func hideTemporarily() {
        dismissedThisRecording = true
        if let panel { PanelMotion.disappear(panel) }
    }

    func setVisible(_ visible: Bool) {
        let show = MeetingASRPolicy.shouldShowCaptionsOverlay(
            requested: visible,
            dismissed: dismissedThisRecording,
            hasLiveCoordinator: appState?.transcription != nil)
        guard let panel else { return }
        if show {
            PanelMotion.appear(panel, at: origin(for: panel))
        } else if panel.isVisible {
            PanelMotion.disappear(panel)
        }
    }

    private func origin(for panel: NSPanel) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return panel.frame.origin }
        let size = panel.frame.size
        let x = screen.visibleFrame.midX - size.width / 2
        let y = screen.visibleFrame.minY + 28
        return NSPoint(x: x, y: y)
    }
}
