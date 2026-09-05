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

    @Test func flagsChangedKeyEventPreservesRightCommandDeviceBit() throws {
        let flags = NSEvent.ModifierFlags(
            rawValue: NSEvent.ModifierFlags.command.rawValue | UInt(NX_DEVICERCMDKEYMASK))
        let event = try #require(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: flags,
                timestamp: 12.345,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: UInt16(kVK_RightCommand)))
        #expect(event.keyCode == UInt16(kVK_RightCommand))
        #expect(event.timestamp == 12.345)
        #expect(event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0)
        #expect(
            HotkeyBinding.eventReportsModifierDown(
                keyCode: UInt32(kVK_RightCommand), flags: event.modifierFlags))
    }
}
