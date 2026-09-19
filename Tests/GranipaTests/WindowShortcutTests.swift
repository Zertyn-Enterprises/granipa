import Carbon.HIToolbox
import Testing

@testable import Granipa

@Suite struct WindowShortcutTests {
    @Test func defaultKeyCodesMatchRectangle() {
        #expect(WindowShortcuts.defaultKeyCode(for: .leftHalf) == UInt32(kVK_LeftArrow))
        #expect(WindowShortcuts.defaultKeyCode(for: .rightHalf) == UInt32(kVK_RightArrow))
        #expect(WindowShortcuts.defaultKeyCode(for: .maximize) == UInt32(kVK_Return))
        #expect(WindowShortcuts.defaultKeyCode(for: .center) == UInt32(kVK_ANSI_C))
        #expect(WindowShortcuts.defaultKeyCode(for: .restore) == UInt32(kVK_Delete))
    }

    @Test func chordLabelUsesMacroGlyph() {
        #expect(
            WindowShortcuts.chordLabel(for: .leftHalf, hyper: .off)
                .contains("⌃⌥"))
        #expect(
            WindowShortcuts.chordLabel(for: .leftHalf, hyper: .capsLock)
                .hasPrefix("⇪"))
        #expect(
            WindowShortcuts.chordLabel(for: .clipboard, hyper: .off)
                .contains("⌥⇧"))
        #expect(
            WindowShortcuts.chordLabel(for: .clipboard, hyper: .capsLock)
                == "⇪V")
        #expect(WindowShortcuts.keyName(UInt32(kVK_LeftArrow)) == "←")
        #expect(WindowShortcuts.keyName(UInt32(kVK_ANSI_C)) == "C")
    }

    @Test func commandArrowChordLabel() {
        let cmd = UInt32(cmdKey)
        #expect(HotkeyBinding.modifierGlyph(cmd) == "⌘")
        #expect(
            WindowShortcuts.chordLabel(
                keyCode: UInt32(kVK_RightArrow), modifiers: cmd, hyper: .off)
                == "⌘→")
        #expect(
            WindowShortcuts.chordLabel(
                keyCode: UInt32(kVK_LeftArrow), modifiers: cmd, hyper: .off)
                == "⌘←")
        #expect(
            WindowShortcuts.chordLabel(
                keyCode: UInt32(kVK_UpArrow), modifiers: cmd, hyper: .off)
                == "⌘↑")
    }

    @Test func extraShortcutDefaults() {
        #expect(ExtraShortcut.clipboard.hotkeyID == 1)
        #expect(ExtraShortcut.ocr.hotkeyID == 2)
        #expect(ExtraShortcut.emoji.hotkeyID == 5)
        #expect(ExtraShortcut.history.hotkeyID == 6)
        #expect(ExtraShortcut.clipboard.defaultKeyCode == UInt32(kVK_ANSI_V))
        #expect(ExtraShortcut.history.defaultKeyCode == UInt32(kVK_ANSI_H))
    }

    @Test func hotkeyIDsAreStable() {
        #expect(WindowAction.leftHalf.hotkeyID == 100)
        #expect(WindowAction.restore.hotkeyID == 113)
    }

    @Test func storedKeyCodeRoundTrip() {
        let defaults = UserDefaults.standard
        let key = WindowShortcuts.defaultsKey(for: .leftHalf)
        let previous = defaults.object(forKey: key)
        defaults.set(Int(kVK_ANSI_H), forKey: key)
        #expect(WindowShortcuts.keyCode(for: .leftHalf) == UInt32(kVK_ANSI_H))
        if let previous {
            defaults.set(previous, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
