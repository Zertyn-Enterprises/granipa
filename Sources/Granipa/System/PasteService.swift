import AppKit
import ApplicationServices
import Carbon.HIToolbox
import Foundation

@MainActor
enum PasteService {
    /// Marks the app's own ⌘V so the macro-key tap lets it through.
    nonisolated static let syntheticEventTag: Int64 = 0x4752_4E50

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
        keyDown.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        keyUp.setIntegerValueField(.eventSourceUserData, value: syntheticEventTag)
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    /// Pastes `text` with ⌘V, then puts back what the user had copied.
    /// Returns false (clipboard untouched) when it cannot auto-paste.
    static func pastePreservingClipboard(_ text: String) -> Bool {
        guard isTrusted else {
            requestTrust()
            return false
        }
        let pasteboard = NSPasteboard.general
        let saved = ClipboardSnapshot(pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Keeps the momentary text out of clipboard history (ClipboardMonitor skips it).
        pasteboard.setData(Data(), forType: ClipboardSnapshot.transientType)
        let written = pasteboard.changeCount
        guard pasteToFrontmostApp() else {
            saved.restore(to: pasteboard, ifUnchangedSince: written)
            return false
        }
        Task {
            // The target app reads the pasteboard when it handles ⌘V, not when it is posted.
            try? await Task.sleep(for: .milliseconds(1500))
            saved.restore(to: pasteboard, ifUnchangedSince: written)
        }
        return true
    }
}

/// A deep copy of every item on a pasteboard, so it survives `clearContents()`.
struct ClipboardSnapshot {
    static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    private let items: [NSPasteboardItem]

    init(_ pasteboard: NSPasteboard) {
        items = (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    /// Skipped when anything else wrote to the pasteboard since `changeCount`:
    /// that newer copy is the user's.
    func restore(to pasteboard: NSPasteboard, ifUnchangedSince changeCount: Int) {
        guard pasteboard.changeCount == changeCount else { return }
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}
