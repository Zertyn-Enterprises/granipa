import AppKit
import SwiftUI

@MainActor
final class ToastController {
    static let shared = ToastController()
    private var panel: NSPanel?

    enum ToastStyle {
        case success
        case warning

        var color: Color {
            switch self {
            case .success: Theme.statusDone
            case .warning: Theme.statusFailed
            }
        }
    }

    // Top-center: the bottom strip belongs to the dictation and captions overlays.
    func show(_ message: String, style: ToastStyle = .success) {
        panel?.orderOut(nil)

        let host = NSHostingView(rootView: ToastView(message: message, style: style))
        let size = host.fittingSize
        let toast = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        toast.level = .statusBar
        toast.isOpaque = false
        toast.backgroundColor = .clear
        toast.hasShadow = true
        toast.ignoresMouseEvents = true
        toast.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        toast.contentView = host
        if let screen = NSScreen.main {
            let x = screen.visibleFrame.midX - size.width / 2
            let y = screen.visibleFrame.maxY - size.height - 60
            PanelMotion.appear(toast, at: NSPoint(x: x, y: y))
        } else {
            toast.orderFrontRegardless()
        }
        panel = toast

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(style == .warning ? 2.4 : 1.8))
            guard let self, self.panel === toast else { return }
            PanelMotion.disappear(toast) {
                if self.panel === toast { self.panel = nil }
            }
        }
    }
}

private struct ToastView: View {
    let message: String
    let style: ToastController.ToastStyle

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(style.color)
                .frame(width: 7, height: 7)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(style.color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.border, lineWidth: 1))
        .padding(6)
    }
}
