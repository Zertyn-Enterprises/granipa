import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing

@testable import Granipa

@Suite struct MacroKeyHoldTests {
    private let f18 = CapsLockRemap.f18KeyCode
    private let v = UInt32(kVK_ANSI_V)
    private let clipboardID: UInt32 = 1

    private func layer() -> HyperLayer {
        HyperLayer(hyperKeyCode: f18, bindings: [v: clipboardID])
    }

    @Test func boundKeyFiresOnlyWhileTheMacroKeyIsHeld() {
        var layer = layer()
        #expect(layer.handle(code: v, type: .keyDown, fromSelf: false) == .pass)

        #expect(layer.handle(code: f18, type: .keyDown, fromSelf: false) == .swallow)
        #expect(layer.handle(code: v, type: .keyDown, fromSelf: false) == .action(clipboardID))

        #expect(layer.handle(code: f18, type: .keyUp, fromSelf: false) == .swallow)
        #expect(layer.handle(code: v, type: .keyDown, fromSelf: false) == .pass)
    }

    @Test func ownPostedPastePassesEvenWhileHeld() {
        var layer = layer()
        _ = layer.handle(code: f18, type: .keyDown, fromSelf: false)
        #expect(layer.handle(code: v, type: .keyDown, fromSelf: true) == .pass)
        #expect(layer.isHeld)
    }

    @Test func autoRepeatKeepsTheLayerHeld() {
        var layer = layer()
        _ = layer.handle(code: f18, type: .keyDown, fromSelf: false)
        _ = layer.handle(code: f18, type: .keyDown, fromSelf: false)
        #expect(layer.handle(code: v, type: .keyDown, fromSelf: false) == .action(clipboardID))
    }

    @Test func remapIsAddedOnceAndRemovedWithoutTouchingOthers() {
        let other: [String: UInt64] = [
            "HIDKeyboardModifierMappingSrc": 0x7_0000_00E0,
            "HIDKeyboardModifierMappingDst": 0x7_0000_00E3,
        ]
        let enabled = CapsLockRemap.merged([other], enabled: true)
        #expect(enabled.count == 2)
        #expect(enabled.contains(other))
        #expect(CapsLockRemap.merged(enabled, enabled: true) == enabled)
        #expect(CapsLockRemap.merged(enabled, enabled: false) == [other])
        #expect(CapsLockRemap.merged([], enabled: false).isEmpty)
    }

    @Test func remapIsOnlyRemovedWhenGranipaInstalledIt() {
        #expect(CapsLockRemap.change(present: false, owned: false, enabled: true) == .install)
        #expect(CapsLockRemap.change(present: true, owned: false, enabled: true) == .none)
        #expect(CapsLockRemap.change(present: true, owned: true, enabled: true) == .none)
        #expect(CapsLockRemap.change(present: true, owned: true, enabled: false) == .remove)
        // Another tool's identical mapping survives Grañipa's cleanup.
        #expect(CapsLockRemap.change(present: true, owned: false, enabled: false) == .none)
        #expect(CapsLockRemap.change(present: false, owned: true, enabled: false) == .none)
    }

    @Test func remapFollowsTheEventTapNotTheSetting() throws {
        let hub = try granipaSource("Sources/Granipa/System/ShortcutHub.swift")
        let start = try #require(hub.range(of: "HyperKeyMonitor.shared.start("))
        let remap = try #require(
            hub.range(of: "CapsLockRemap.apply(enabled: hyper == .capsLock && started)"))
        #expect(start.lowerBound < remap.lowerBound)
    }
}

private func granipaSource(_ relativePath: String) throws -> String {
    let testsFile = URL(fileURLWithPath: #filePath)
    let repo = testsFile.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repo.appendingPathComponent(relativePath), encoding: .utf8)
}
