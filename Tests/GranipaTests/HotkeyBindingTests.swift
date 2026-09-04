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

    @Test func rightCommandEdgesComeFromTheEventDeviceBit() {
        let rightDown = NSEvent.ModifierFlags(
            rawValue: NSEvent.ModifierFlags.command.rawValue | UInt(NX_DEVICERCMDKEYMASK))
        #expect(
            HotkeyBinding.eventReportsModifierDown(
                keyCode: UInt32(kVK_RightCommand), flags: rightDown))
        #expect(
            !HotkeyBinding.eventReportsModifierDown(
                keyCode: UInt32(kVK_RightCommand), flags: .command))
        #expect(
            !HotkeyBinding.eventReportsModifierDown(
                keyCode: UInt32(kVK_RightCommand), flags: []))
    }
}
