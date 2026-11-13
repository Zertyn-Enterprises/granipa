import Carbon.HIToolbox
import CoreGraphics
import Foundation
import Testing

@testable import Granipa

@Suite struct MacroKeyHoldTests {
    private let f18 = CapsLockRemap.f18KeyCode
    private let v = UInt32(kVK_ANSI_V)
    private let clipboardID: UInt32 = 1

    private func route(
        _ code: UInt32, _ type: CGEventType, armed: inout Bool
    ) -> HyperKeyRoute {
        HyperKeyRoute.route(
            type: type, code: code, flags: [], synthetic: false,
            hyper: f18, bindings: [v: clipboardID], armed: &armed)
    }

    @Test func boundKeyFiresOnlyWhileTheMacroKeyIsHeld() {
        var armed = false
        #expect(route(v, .keyDown, armed: &armed) == .pass)

        #expect(route(f18, .keyDown, armed: &armed) == .swallow)
        #expect(route(v, .keyDown, armed: &armed) == .fire(clipboardID))

        #expect(route(f18, .keyUp, armed: &armed) == .swallow)
        #expect(route(v, .keyDown, armed: &armed) == .pass)
    }

    @Test func aDisabledTapReleasesTheLayer() {
        var armed = false
        _ = route(f18, .keyDown, armed: &armed)
        #expect(route(0, .tapDisabledByTimeout, armed: &armed) == .pass)
        #expect(route(v, .keyDown, armed: &armed) == .pass)
    }

    @Test func autoRepeatKeepsTheLayerHeld() {
        var armed = false
        _ = route(f18, .keyDown, armed: &armed)
        _ = route(f18, .keyDown, armed: &armed)
        #expect(route(v, .keyDown, armed: &armed) == .fire(clipboardID))
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
