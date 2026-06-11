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

    func registerHotkeys() {
        let bindings: [(id: UInt32, key: Int, action: WindowAction)] = [
            (100, kVK_LeftArrow, .leftHalf),
            (101, kVK_RightArrow, .rightHalf),
            (102, kVK_UpArrow, .topHalf),
            (103, kVK_DownArrow, .bottomHalf),
            (104, kVK_Return, .maximize),
            (105, kVK_ANSI_C, .center),
            (106, kVK_ANSI_U, .topLeft),
            (107, kVK_ANSI_I, .topRight),
            (108, kVK_ANSI_J, .bottomLeft),
            (109, kVK_ANSI_K, .bottomRight),
            (110, kVK_ANSI_D, .firstThird),
            (111, kVK_ANSI_F, .centerThird),
            (112, kVK_ANSI_G, .lastThird),
            (113, kVK_Delete, .restore),
        ]
        for binding in bindings {
            HotkeyManager.shared.register(
                id: binding.id,
                keyCode: UInt32(binding.key),
                modifiers: UInt32(controlKey | optionKey)
            ) { [weak self] in
                self?.perform(binding.action)
            }
        }
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

        guard let screen = visibleFrameAX(forWindowFrame: current),
            let target = WindowLayout.frame(for: action, screen: screen, current: current)
        else { return }

        if lastSnap == nil || !CFEqual(lastSnap!.window, window) {
            lastSnap = (window, current)
        }
        setFrame(target, on: window)
    }

    // MARK: - Accessibility plumbing

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
