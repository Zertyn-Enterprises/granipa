import AppKit
import SwiftUI

@MainActor
final class DictationOverlayController {
    static let shared = DictationOverlayController()
    private static let panelSize = NSSize(width: 472, height: 164)
    private var panel: NSPanel?

    func attach(_ controller: DictationController) {
        DictationSessionClock.shared.beginObserving()
        if panel != nil { return }
        let host = NSHostingView(
            rootView: AnyView(DictationOverlayView().environment(controller)))

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
        panel.alphaValue = 0
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        self.panel = panel
    }

    func setVisible(_ visible: Bool) {
        guard let panel else { return }
        if visible {
            PanelMotion.appear(panel, at: origin(for: panel))
        } else if panel.isVisible {
            PanelMotion.disappear(panel)
        }
    }

    func setClickThrough(_ through: Bool) {
        panel?.ignoresMouseEvents = through
    }

    private func origin(for panel: NSPanel) -> NSPoint {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return panel.frame.origin }
        let size = panel.frame.size
        let x = screen.visibleFrame.midX - size.width / 2
        let y = screen.visibleFrame.minY + 150
        return NSPoint(x: x, y: y)
    }
}
