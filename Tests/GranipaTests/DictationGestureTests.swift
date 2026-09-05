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

    @Test func tapStaysListeningAndSecondPressStopsOnce() async {
        var captures = 0
        let controller = hookedController(beforeCapture: {
            captures += 1
        })
        defer { controller.cancel() }

        controller.handlePress(at: 1.0)
        controller.handleRelease(at: 1.05)
        #expect(await waitUntil { controller.phase == .listening })
        #expect(controller.isToggle)
        #expect(captures == 1)

        controller.handlePress(at: 2.0)
        controller.handleRelease(at: 2.04)
        #expect(
            await waitUntil {
                controller.phase != .listening && controller.phase != .preparing
            })
        #expect(controller.phase != .listening)
        #expect(controller.phase != .preparing)
        #expect(captures == 1)
    }

    @Test func holdReleaseBeforeCaptureDoesNotReopenOrFakeRetry() async {
        let gate = CaptureGate()
        let controller = hookedController(
            beforeCapture: { await gate.wait() },
            transcribe: { chunks in
                for await _ in chunks {}
                return ""
            })
        defer {
            gate.open()
            controller.cancel()
        }

        controller.handlePress(at: 10.0)
        #expect(controller.phase == .preparing)
        controller.handleRelease(at: 10.40)
        #expect(
            await waitUntil {
                controller.phase != .preparing && controller.phase != .listening
            })
        gate.open()
        try? await Task.sleep(for: .milliseconds(40))

        #expect(!controller.hasOpenCapture)
        #expect(controller.phase != .listening)
        if case .failed(let message) = controller.phase {
            #expect(!message.contains("Didn't catch that"))
        }
    }

    @Test func secondPressWhilePreparingDoesNotReopenCapture() async {
        let gate = CaptureGate()
        let controller = hookedController(beforeCapture: { await gate.wait() })
        defer {
            gate.open()
            controller.cancel()
        }

        controller.handlePress(at: 3.0)
        #expect(controller.phase == .preparing)
        controller.handlePress(at: 3.10)
        controller.handleRelease(at: 3.12)
        gate.open()
        try? await Task.sleep(for: .milliseconds(40))

        #expect(!controller.hasOpenCapture)
        #expect(controller.phase != .listening)
    }

    @Test func menuAndRetryLatchUntilStopped() async {
        let controller = hookedController(
            captureError: DictationError.audioFormat)
        defer { controller.cancel() }

        controller.toggleFromMenu()
        #expect(controller.isToggle)
        #expect(controller.phase.isActive)
        #expect(
            await waitUntil {
                if case .failed = controller.phase { return true }
                return false
            })
        #expect(controller.lastFailureRetryable)

        controller.retry()
        #expect(controller.isToggle)
        #expect(controller.phase == .preparing || controller.phase == .listening)
        #expect(
            await waitUntil {
                if case .failed = controller.phase { return true }
                return false
            })
        if case .failed(let message) = controller.phase {
            #expect(message == DictationError.audioFormat.errorDescription)
        }
    }

    @Test func holdAfterListeningCommitsBufferedText() async {
        var committed: String?
        let controller = hookedController(transcribe: { chunks in
            for await _ in chunks {}
            return "hello"
        })
        controller.onCommitted = { text, _, _ in committed = text }
        defer { controller.cancel() }

        controller.handlePress(at: 8.0)
        #expect(await waitUntil { controller.phase == .listening })
        controller.handleRelease(at: 8.50)
        #expect(await waitUntil { controller.phase == .done || committed != nil })
        #expect(committed == "hello")
        #expect(controller.preview == "hello")
    }

    @Test func cancelClearsToggleAndDropsStalePreview() async {
        let controller = hookedController()
        defer { controller.cancel() }

        controller.toggleFromMenu()
        #expect(await waitUntil { controller.phase.isActive })
        let oldGeneration = controller.testSessionGeneration
        controller.cancel()
        #expect(controller.phase == .idle)
        #expect(!controller.isToggle)

        controller.handlePress(at: 9.0)
        controller.handleRelease(at: 9.05)
        #expect(await waitUntil { controller.phase.isActive })
        controller.publishPreviewForTesting("stale", generation: oldGeneration)
        #expect(controller.preview != "stale")
    }

    @Test func unmatchedReleaseDoesNotStartASession() {
        let controller = hookedController()
        defer { controller.cancel() }
        controller.handleRelease(at: 1.0)
        #expect(controller.phase == .idle)
        #expect(!controller.isToggle)
        #expect(!controller.hasOpenCapture)
    }

    @Test func partialDuringListeningStillUpdatesPreview() async {
        let controller = hookedController()
        defer { controller.cancel() }

        controller.handlePress(at: 4.0)
        controller.handleRelease(at: 4.05)
        #expect(await waitUntil { controller.phase == .listening })
        let generation = controller.testSessionGeneration
        controller.publishPreviewForTesting("partial", generation: generation)
        #expect(controller.preview == "partial")
        #expect(controller.phase == .listening)
    }

    @Test func latePartialAfterDoneDoesNotOverwriteCommittedPreview() async {
        var committed: String?
        let controller = hookedController(transcribe: { chunks in
            for await _ in chunks {}
            return "hello"
        })
        controller.onCommitted = { text, _, _ in committed = text }
        defer { controller.cancel() }

        controller.handlePress(at: 6.0)
        #expect(await waitUntil { controller.phase == .listening })
        let generation = controller.testSessionGeneration
        controller.publishPreviewForTesting("partial", generation: generation)
        #expect(controller.preview == "partial")

        controller.handleRelease(at: 6.50)
        #expect(await waitUntil { controller.phase == .done })
        #expect(committed == "hello")
        #expect(controller.preview == "hello")

        controller.publishPreviewForTesting("late", generation: generation)
        #expect(controller.phase == .done)
        #expect(controller.preview == "hello")
        #expect(committed == "hello")
    }

    @Test func latePartialAfterFailureDoesNotOverwriteFailedState() async {
        let controller = hookedController(captureError: DictationError.audioFormat)
        defer { controller.cancel() }

        controller.toggleFromMenu()
        #expect(
            await waitUntil {
                if case .failed = controller.phase { return true }
                return false
            })
        let generation = controller.testSessionGeneration
        #expect(controller.preview == "")
        controller.publishPreviewForTesting("late", generation: generation)
        #expect(controller.preview == "")
        if case .failed(let message) = controller.phase {
            #expect(message == DictationError.audioFormat.errorDescription)
        } else {
            Issue.record("expected failed phase")
        }
        #expect(controller.lastFailureRetryable)
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
private final class CaptureGate {
    private var opened = false

    func wait() async {
        while !opened {
            if Task.isCancelled { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    func open() {
        opened = true
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
    timeout: Duration = .milliseconds(800), _ condition: @MainActor () -> Bool
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
