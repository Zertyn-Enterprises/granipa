import AppKit
import ApplicationServices
import Carbon.HIToolbox

@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var lastSnap: (window: AXUIElement, frame: CGRect)?

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "windowSnappingEnabled") as? Bool ?? true
    }

    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "windowSnappingEnabled")
        ShortcutHub.shared.rebind()
    }

    func perform(_ action: WindowAction) {
        guard isEnabled else { return }
        guard PasteService.isTrusted else {
            PasteService.requestTrust()
            return
        }
        guard let window = focusedWindow(), let current = frame(of: window) else { return }

        if action == .restore {
            if let last = lastSnap, CFEqual(last.window, window) {
                setFrame(last.frame, on: window)
                lastSnap = nil
            }
            return
        }

        guard let screen = visibleFrameAX(forWindowFrame: current) else { return }
        let usable = WindowLayout.usableFrame(
            screen: screen,
            stageStrip: WindowInventory.stageStripSide,
            stripWindows: WindowInventory.onscreenFrames().filter {
                !WindowLayout.isSame($0, current)
            })

        if action == .tileAppWindows {
            tileFrontmostAppWindows(on: screen, into: usable)
            return
        }

        let occupied = WindowInventory.occupiedFrames(on: usable, ignoring: current)
        guard let target = WindowLayout.frame(
            for: action, screen: usable, current: current, occupied: occupied)
        else { return }

        if lastSnap == nil || !CFEqual(lastSnap!.window, window) {
            lastSnap = (window, current)
        }
        setFrame(target, on: window)
    }

    /// Grids the frontmost app's windows that sit on this screen and on the
    /// current stage; windows parked in the Stage Manager strip stay there.
    private func tileFrontmostAppWindows(on screen: CGRect, into usable: CGRect) {
        guard let app = NSWorkspace.shared.frontmostApplication else { return }
        let onStage = WindowInventory.onscreenFrames(pid: app.processIdentifier)
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &ref)
                == .success,
            let windows = ref as? [AXUIElement]
        else { return }

        // Native tabs are separate AX windows sharing one frame; keep one per group.
        var tileable: [(window: AXUIElement, frame: CGRect)] = []
        for window in windows {
            guard isTileable(window), let frame = frame(of: window),
                screen.contains(CGPoint(x: frame.midX, y: frame.midY)),
                onStage.contains(where: { WindowLayout.isSame($0, frame) }),
                !tileable.contains(where: { WindowLayout.isSame($0.frame, frame) })
            else { continue }
            tileable.append((window, frame))
        }
        let order = WindowLayout.tileOrder(tileable.map(\.frame))
        let targets = WindowLayout.gridFrames(count: tileable.count, screen: usable)
        for (target, index) in zip(targets, order) {
            setFrame(target, on: tileable[index].window)
        }
    }

    // MARK: - Accessibility plumbing

    private func isTileable(_ window: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        var minimized: CFTypeRef?
        var fullScreen: CFTypeRef?
        AXUIElementCopyAttributeValue(window, kAXSubroleAttribute as CFString, &subrole)
        AXUIElementCopyAttributeValue(window, kAXMinimizedAttribute as CFString, &minimized)
        AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullScreen)
        return subrole as? String == kAXStandardWindowSubrole as String
            && minimized as? Bool != true
            && fullScreen as? Bool != true
    }

    private func focusedWindow() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var ref: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            axApp, kAXFocusedWindowAttribute as CFString, &ref)
        guard result == .success, let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else {
            return nil
        }
        return (ref as! AXUIElement)
    }

    private func frame(of window: AXUIElement) -> CGRect? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                window, kAXPositionAttribute as CFString, &positionRef) == .success,
            AXUIElementCopyAttributeValue(
                window, kAXSizeAttribute as CFString, &sizeRef) == .success,
            let positionRef, let sizeRef
        else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionRef as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    private func setFrame(_ frame: CGRect, on window: AXUIElement) {
        var point = frame.origin
        var size = frame.size
        if let position = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
        if let sizeValue = AXValueCreate(.cgSize, &size) {
            AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, sizeValue)
        }
        // Re-set position: some apps clamp the origin while resizing.
        if let position = AXValueCreate(.cgPoint, &point) {
            AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, position)
        }
    }

    // Converts the visible frame of the screen hosting the window into AX
    // (top-left origin) coordinates, where AX (0,0) is the primary screen's top-left.
    private func visibleFrameAX(forWindowFrame windowFrame: CGRect) -> CGRect? {
        guard let primary = NSScreen.screens.first else { return nil }
        let primaryHeight = primary.frame.maxY
        let centerAppKit = CGPoint(
            x: windowFrame.midX,
            y: primaryHeight - windowFrame.midY)
        let screen =
            NSScreen.screens.first { $0.frame.contains(centerAppKit) }
            ?? NSScreen.main ?? primary
        let visible = screen.visibleFrame
        return CGRect(
            x: visible.minX,
            y: primaryHeight - visible.maxY,
            width: visible.width,
            height: visible.height)
    }
}
