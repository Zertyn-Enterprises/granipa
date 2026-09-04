import AppKit
import SwiftUI

private final class HistoryKeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class DictationHistoryPanelController: NSObject, NSWindowDelegate {
    static let shared = DictationHistoryPanelController()
    private var panel: HistoryKeyablePanel?
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
        let content = DictationHistoryView(onClose: { [weak self] in self?.hide() })
            .environment(appState)
        let host = NSHostingView(rootView: AnyView(content))

        let panel: HistoryKeyablePanel
        if let existing = self.panel {
            panel = existing
            panel.contentView = host
        } else {
            panel = HistoryKeyablePanel(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
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
                at: NSPoint(x: frame.midX - 280, y: frame.midY - 280),
                makeKey: true)
        } else {
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func hide() {
        guard let panel else { return }
        PanelMotion.disappear(panel)
    }

    nonisolated func windowDidResignKey(_ notification: Notification) {
        Task { @MainActor in
            self.hide()
        }
    }
}
