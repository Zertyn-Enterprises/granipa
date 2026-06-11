import ApplicationServices
import Carbon.HIToolbox
import Foundation

@MainActor
enum PasteService {
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    static func requestTrust() {
        // Literal key for kAXTrustedCheckOptionPrompt; the global is not
        // concurrency-safe to reference under Swift 6.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    static func pasteToFrontmostApp() -> Bool {
        guard AXIsProcessTrusted() else {
            requestTrust()
            return false
        }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let keyDown = CGEvent(
                keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let keyUp = CGEvent(
                keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
