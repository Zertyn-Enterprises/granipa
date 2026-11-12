import AppKit
import QuartzCore

/// Shared open/close for every floating panel (dictation, clipboard, history,
/// captions, toast). Superwhisper/Raycast-style: fade + 40pt rise, ease-out expo.
@MainActor enum PanelMotion {
    static let showDuration: TimeInterval = 0.34
    static let hideDuration: TimeInterval = 0.20
    static let rise: CGFloat = 40

    private static var showTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.16, 1.0, 0.3, 1.0)
    }

    private static var hideTiming: CAMediaTimingFunction {
        CAMediaTimingFunction(controlPoints: 0.4, 0.0, 1.0, 1.0)
    }

    /// Bumped on every appear/disappear, so the completion of a hide that was
    /// interrupted by a re-show does not order the panel out again.
    private static var generations: [ObjectIdentifier: Int] = [:]

    private static func bump(_ panel: NSPanel) -> Int {
        let next = (generations[ObjectIdentifier(panel)] ?? 0) + 1
        generations[ObjectIdentifier(panel)] = next
        return next
    }

    static var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    static func appear(_ panel: NSPanel, at origin: NSPoint, makeKey: Bool = false) {
        _ = bump(panel)
        panel.contentView?.wantsLayer = true
        let start = NSPoint(x: origin.x, y: origin.y - rise)
        panel.setFrameOrigin(start)
        panel.alphaValue = 0
        if makeKey {
            panel.makeKeyAndOrderFront(nil)
        } else {
            panel.orderFrontRegardless()
        }
        if reduceMotion {
            panel.setFrameOrigin(origin)
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = showDuration
            ctx.timingFunction = showTiming
            panel.animator().alphaValue = 1
            panel.animator().setFrameOrigin(origin)
        }
    }

    static func disappear(
        _ panel: NSPanel, then: (@MainActor @Sendable () -> Void)? = nil
    ) {
        if reduceMotion {
            panel.alphaValue = 0
            panel.orderOut(nil)
            then?()
            return
        }
        let token = bump(panel)
        let dest = NSPoint(x: panel.frame.origin.x, y: panel.frame.origin.y - rise)
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = hideDuration
                ctx.timingFunction = hideTiming
                panel.animator().alphaValue = 0
                panel.animator().setFrameOrigin(dest)
            },
            completionHandler: {
                Task { @MainActor in
                    if generations[ObjectIdentifier(panel)] == token {
                        generations[ObjectIdentifier(panel)] = nil
                        panel.orderOut(nil)
                    }
                    then?()
                }
            })
    }
}
