import AppKit
import Carbon.HIToolbox

enum EmojiPalette {
    /// Posts the system emoji shortcut (⌃⌘Space) into the front app.
    /// `CharacterPalette.app` is an input method — opening it as an app shows nothing.
    @MainActor
    static func show() {
        if PasteService.isTrusted, postSystemShortcut() { return }
        if !PasteService.isTrusted { PasteService.requestTrust() }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontCharacterPalette(nil)
    }

    private static func postSystemShortcut() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(
                keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Space), keyDown: true),
            let up = CGEvent(
                keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Space), keyDown: false)
        else { return false }
        down.flags = [.maskControl, .maskCommand]
        up.flags = [.maskControl, .maskCommand]
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        return true
    }
}
