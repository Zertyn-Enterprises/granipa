import AppKit
import Carbon.HIToolbox
import Foundation
import Testing

@testable import Granipa

/// Tap/hold and session lifecycle against the production controller, without
/// opening the user microphone. The hardware `beginCapture` micBusy path stays
/// in DictationTests.
@Suite(.serialized)
@MainActor
struct DictationGestureTests {
    @Test func delayedHandlingDoesNotTurnTapIntoHold() async {
        let controller = hookedController()
        defer { controller.cancel() }

        controller.handlePress(at: 100)
        #expect(controller.phase == .preparing || controller.phase == .listening)
        try? await Task.sleep(for: .milliseconds(300))
        controller.handleRelease(at: 100.05)

        #expect(controller.isToggle)
        #expect(controller.phase == .preparing || controller.phase == .listening)
    }
}

@Suite(.serialized)
struct HotkeyDispatchTests {
    @Test @MainActor func modifierHandlersReceivePhysicalEventTimestamp() async throws {
        let id: UInt32 = 941
        var pressedAt: TimeInterval?
        var releasedAt: TimeInterval?
        HotkeyManager.shared.register(
            id: id,
            keyCode: UInt32(kVK_RightCommand),
            modifiers: 0,
            onPress: { pressedAt = $0 },
            onRelease: { releasedAt = $0 }
        )
        defer { HotkeyManager.shared.unregister(id: id) }

        let hardwarePress: TimeInterval = 12.345
        let hardwareRelease: TimeInterval = 12.400
        let down = try flagsChangedEvent(
            down: true, timestamp: hardwarePress, isARepeat: false)
        let up = try flagsChangedEvent(
            down: false, timestamp: hardwareRelease, isARepeat: false)
        #expect(down.timestamp == hardwarePress)
        #expect(up.timestamp == hardwareRelease)

        HotkeyManager.shared.handleModifierEvent(down)
        HotkeyManager.shared.handleModifierEvent(up)
        let received = await waitUntil(timeout: .milliseconds(800)) {
            pressedAt != nil && releasedAt != nil
        }

        #expect(received)
        #expect(pressedAt == hardwarePress)
        #expect(releasedAt == hardwareRelease)
        #expect(pressedAt != ProcessInfo.processInfo.systemUptime)
    }

    @Test @MainActor func modifierIgnoresDuplicateDownUpAndAutorepeat() async throws {
        let id: UInt32 = 942
        var presses = 0
        var releases = 0
        HotkeyManager.shared.register(
            id: id,
            keyCode: UInt32(kVK_RightCommand),
            modifiers: 0,
            onPress: { _ in presses += 1 },
            onRelease: { _ in releases += 1 }
        )
        defer { HotkeyManager.shared.unregister(id: id) }

        let down = try flagsChangedEvent(down: true, timestamp: 1.0, isARepeat: false)
        let downRepeat = try flagsChangedEvent(down: true, timestamp: 1.03, isARepeat: true)
        let up = try flagsChangedEvent(down: false, timestamp: 1.4, isARepeat: false)
        let upAgain = try flagsChangedEvent(down: false, timestamp: 1.5, isARepeat: false)

        HotkeyManager.shared.handleModifierEvent(down)
        HotkeyManager.shared.handleModifierEvent(downRepeat)
        HotkeyManager.shared.handleModifierEvent(up)
        HotkeyManager.shared.handleModifierEvent(upAgain)
        let received = await waitUntil(timeout: .milliseconds(800)) {
            presses >= 1 && releases >= 1
        }

        #expect(received)
        #expect(presses == 1)
        #expect(releases == 1)
    }

    @Test @MainActor func carbonHotkeyIgnoresRepeatAndUnmatchedRelease() {
        let id: UInt32 = 943
        var presses = 0
        var releases = 0
        HotkeyManager.shared.register(
            id: id,
            keyCode: UInt32(kVK_Space),
            modifiers: UInt32(optionKey),
            onPress: { _ in presses += 1 },
            onRelease: { _ in releases += 1 }
        )
        defer { HotkeyManager.shared.unregister(id: id) }

        HotkeyManager.shared.dispatchHotKey(id: id, released: false, timestamp: 1.0)
        HotkeyManager.shared.dispatchHotKey(id: id, released: false, timestamp: 1.02)
        HotkeyManager.shared.dispatchHotKey(id: id, released: true, timestamp: 1.4)
        HotkeyManager.shared.dispatchHotKey(id: id, released: true, timestamp: 1.5)

        #expect(presses == 1)
        #expect(releases == 1)
    }

    @Test func dictationHotkeyPassesEventTimestampsAndCarbonCallersStaySimple() throws {
        let app = try granipaSource("Sources/Granipa/AppState.swift")
        #expect(app.contains("handlePress(at:"))
        #expect(app.contains("handleRelease(at:"))

        let hotkey = try granipaSource("Sources/Granipa/System/HotkeyManager.swift")
        #expect(hotkey.contains("event.timestamp"))
        #expect(hotkey.contains("GetEventTime(event)"))

        let hub = try granipaSource("Sources/Granipa/System/ShortcutHub.swift")
        #expect(hub.contains("HotkeyManager.shared.register("))
        #expect(hub.contains("Self.dispatch(extra.hotkeyID)"))
        #expect(!hub.contains("handlePress(at:"))
    }
}

@MainActor
private func hookedController(
    beforeCapture: (@MainActor () async -> Void)? = nil,
    captureError: Error? = nil,
    transcribe: (@MainActor (AsyncStream<AudioChunk>) async throws -> String)? = nil
) -> DictationController {
    DictationController(
        testHooks: DictationTestHooks(
            beforeCapture: beforeCapture,
            captureError: captureError,
            transcribe: transcribe ?? { chunks in
                for await _ in chunks {}
                return "ok"
            }
        ))
}

private func flagsChangedEvent(
    down: Bool, timestamp: TimeInterval, isARepeat: Bool
) throws -> NSEvent {
    let flags: NSEvent.ModifierFlags =
        down
        ? NSEvent.ModifierFlags(
            rawValue: NSEvent.ModifierFlags.command.rawValue | UInt(NX_DEVICERCMDKEYMASK))
        : []
    guard
        let event = NSEvent.keyEvent(
            with: .flagsChanged,
            location: .zero,
            modifierFlags: flags,
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: isARepeat,
            keyCode: UInt16(kVK_RightCommand))
    else {
        throw NSError(
            domain: "GranipaTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "flagsChanged NSEvent was nil"])
    }
    return event
}

@MainActor
private func waitUntil(
    timeout: Duration, _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() { return true }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

private func granipaSource(_ relativePath: String) throws -> String {
    let testsFile = URL(fileURLWithPath: #filePath)
    let repo = testsFile.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    return try String(
        contentsOf: repo.appendingPathComponent(relativePath), encoding: .utf8)
}
