import AppKit
import Carbon.HIToolbox
import Testing

@testable import Granipa

@Suite struct HotkeyBindingTests {
    @Test func rightOptionAloneIsModifierOnly() {
        #expect(HotkeyBinding.modifierFlag(forKeyCode: UInt32(kVK_RightOption)) == .option)
        #expect(HotkeyBinding.isModifierOnly(keyCode: UInt32(kVK_RightOption), modifiers: 0))
    }

    @Test func optionSpaceIsNotModifierOnly() {
        #expect(HotkeyBinding.modifierFlag(forKeyCode: UInt32(kVK_Space)) == nil)
        #expect(
            !HotkeyBinding.isModifierOnly(
                keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey)))
    }

    @Test func rightCommandAloneIsModifierOnly() {
        #expect(HotkeyBinding.modifierFlag(forKeyCode: UInt32(kVK_RightCommand)) == .command)
        #expect(HotkeyBinding.isModifierOnly(keyCode: UInt32(kVK_RightCommand), modifiers: 0))
        #expect(HotkeyBinding.modifierGlyph(UInt32(cmdKey)) == "⌘")
        #expect(HotkeyBinding.modifierGlyph(UInt32(controlKey | optionKey)) == "⌃⌥")
    }
}
