import Carbon.HIToolbox
import CoreGraphics
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
        #expect(WindowAction.tileAppWindows.hotkeyID == 114)
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

    @Test func macroKeyRouting() {
        let rShift = UInt32(kVK_RightShift)
        let rCmd = UInt32(kVK_RightCommand)
        let key = UInt32(kVK_ANSI_V)
        let rShiftDown = CGEventFlags(
            rawValue: CGEventFlags.maskShift.rawValue | UInt64(NX_DEVICERSHIFTKEYMASK))
        let cases: [(UInt32, CGEventType, UInt32, CGEventFlags, Bool, Bool, HyperKeyRoute, Bool)] = [
            // hyper, type, code, flags, synthetic, armed before → route, armed after
            (rShift, .flagsChanged, rShift, rShiftDown, false, false, .pass, true),
            (rShift, .keyDown, key, rShiftDown, false, true, .fire(7), true),
            (rShift, .keyDown, key, [.maskCommand], false, true, .pass, true),
            (rCmd, .keyDown, key, [.maskCommand], false, true, .fire(7), true),
            (rCmd, .keyDown, key, [.maskCommand], true, true, .pass, true),
        ]
        for (hyper, type, code, flags, synthetic, before, route, after) in cases {
            var armed = before
            #expect(
                HyperKeyRoute.route(
                    type: type, code: code, flags: flags, synthetic: synthetic,
                    hyper: hyper, bindings: [key: 7], armed: &armed) == route)
            #expect(armed == after)
        }
    }
}
