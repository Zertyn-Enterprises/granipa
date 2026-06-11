import AppKit
import SwiftUI

@MainActor
final class ToastController {
    static let shared = ToastController()
    private var panel: NSPanel?

    func show(_ message: String) {
        panel?.orderOut(nil)

        let host = NSHostingView(rootView: ToastView(message: message))
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
            toast.setFrameOrigin(NSPoint(x: x, y: y))
        }
        toast.orderFrontRegardless()
        panel = toast

        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.8))
            if self?.panel === toast {
                toast.orderOut(nil)
                self?.panel = nil
            }
        }
    }
}

private struct ToastView: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: 0x4CD981))
                .frame(width: 7, height: 7)
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(hex: 0x4CD981))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color(hex: 0x252B26), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(6)
    }
}
