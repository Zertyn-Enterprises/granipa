import Carbon.HIToolbox
import Foundation

@MainActor
final class ShortcutHub {
    static let shared = ShortcutHub()

    private static let extraIDs: [UInt32] = ExtraShortcut.allCases.map(\.hotkeyID)

    func rebind() {
        for id in Self.extraIDs {
            HotkeyManager.shared.unregister(id: id)
        }
        for action in WindowAction.allCases {
            HotkeyManager.shared.unregister(id: action.hotkeyID)
        }
        HyperKeyMonitor.shared.stop()

        var keyToID: [UInt32: UInt32] = [:]
        for extra in ExtraShortcut.allCases {
            keyToID[ExtraShortcut.keyCode(for: extra)] = extra.hotkeyID
        }
        let snapping =
            UserDefaults.standard.object(forKey: "windowSnappingEnabled") as? Bool ?? true
        if snapping {
            for action in WindowAction.allCases {
                keyToID[WindowShortcuts.keyCode(for: action)] = action.hotkeyID
            }
        }

        if let hyperCode = WindowHyperKey.current.keyCode {
            if !PasteService.isTrusted {
                PasteService.requestTrust()
            }
            HyperKeyMonitor.shared.start(hyperKeyCode: hyperCode, bindings: keyToID) { id in
                Self.dispatch(id)
            }
            return
        }

        for extra in ExtraShortcut.allCases {
            HotkeyManager.shared.register(
                id: extra.hotkeyID,
                keyCode: ExtraShortcut.keyCode(for: extra),
                modifiers: ExtraShortcut.modifiers(for: extra)
            ) {
                Self.dispatch(extra.hotkeyID)
            }
        }
        guard snapping else { return }
        for action in WindowAction.allCases {
            HotkeyManager.shared.register(
                id: action.hotkeyID,
                keyCode: WindowShortcuts.keyCode(for: action),
                modifiers: WindowShortcuts.modifiers(for: action)
            ) {
                WindowManager.shared.perform(action)
            }
        }
    }

    private static func dispatch(_ id: UInt32) {
        switch id {
        case ExtraShortcut.clipboard.hotkeyID:
            ClipboardPanelController.shared.toggle()
        case ExtraShortcut.ocr.hotkeyID:
            Task { await OCRService.captureAndCopy() }
        case ExtraShortcut.emoji.hotkeyID:
            EmojiPalette.show()
        case ExtraShortcut.history.hotkeyID:
            DictationHistoryPanelController.shared.toggle()
        default:
            if let action = WindowAction.allCases.first(where: { $0.hotkeyID == id }) {
                WindowManager.shared.perform(action)
            }
        }
    }
}
