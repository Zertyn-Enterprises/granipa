import AppKit
import SwiftUI

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    static let shared = ClipboardPanelController()
    private var panel: KeyablePanel?
    private weak var appState: AppState?

    func configure(appState: AppState) {
        self.appState = appState
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        guard let appState else { return }
        let content = ClipboardHistoryView(onClose: { [weak self] completion in
            self?.hide(then: completion)
        })
            .environment(appState)
        let host = NSHostingView(rootView: AnyView(content))

        let panel: KeyablePanel
        if let existing = self.panel {
            panel = existing
            panel.contentView = host
        } else {
            panel = KeyablePanel(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 460),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.delegate = self
            panel.contentView = host
            self.panel = panel
        }

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            PanelMotion.appear(
                panel,
                at: NSPoint(x: frame.midX - 400, y: frame.midY - 180),
                makeKey: true)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hide(then completion: (@MainActor @Sendable () -> Void)? = nil) {
        guard let panel else {
            completion?()
            return
        }
        PanelMotion.disappear(panel, then: completion)
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            self.hide()
        }
    }
}
