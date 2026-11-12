import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

/// Hold a dedicated key (Caps Lock, Right Shift, …) then a shortcut. Other apps
/// never see that chord, so it cannot collide with Rectangle / Raycast / browsers.
final class HyperKeyMonitor: @unchecked Sendable {
    static let shared = HyperKeyMonitor()
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "hyper")

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var runLoop: CFRunLoop?
    private var hyperKeyCode: UInt32 = 0
    private var bindings: [UInt32: UInt32] = [:]
    private var hyperDown = false
    private var onAction: (@MainActor (UInt32) -> Void)?

    /// Returns false when the event tap cannot be created (no Accessibility).
    /// The tap runs on its own thread so system-wide typing never waits on the
    /// app's main thread; actions still run on the main actor.
    @discardableResult
    func start(
        hyperKeyCode: UInt32,
        bindings: [UInt32: UInt32],
        onAction: @escaping @MainActor (UInt32) -> Void
    ) -> Bool {
        stop()
        lock.lock()
        self.hyperKeyCode = hyperKeyCode
        self.bindings = bindings
        self.onAction = onAction
        self.hyperDown = false
        lock.unlock()

        let ready = DispatchSemaphore(value: 0)
        let thread = Thread { [self] in
            runTap(signal: ready)
        }
        thread.name = "com.zertyn.granipa.hyper-key"
        thread.qualityOfService = .userInteractive
        thread.start()
        ready.wait()

        lock.lock()
        let started = tap != nil
        lock.unlock()
        if started {
            Self.log.info("hyper key monitor on code=\(hyperKeyCode)")
        } else {
            Self.log.error("CGEvent tap failed — grant Accessibility for the macro key")
        }
        return started
    }

    func stop() {
        lock.lock()
        let tap = self.tap
        let source = self.source
        let runLoop = self.runLoop
        self.tap = nil
        self.source = nil
        self.runLoop = nil
        self.hyperDown = false
        lock.unlock()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let runLoop {
            if let source { CFRunLoopRemoveSource(runLoop, source, .commonModes) }
            CFRunLoopStop(runLoop)
        }
    }

    private func runTap(signal ready: DispatchSemaphore) {
        let mask =
            (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cghidEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: CGEventMask(mask),
                callback: { _, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let monitor = Unmanaged<HyperKeyMonitor>.fromOpaque(refcon)
                        .takeUnretainedValue()
                    return monitor.handle(type: type, event: event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            ready.signal()
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let runLoop = CFRunLoopGetCurrent()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.lock()
        self.tap = tap
        self.source = source
        self.runLoop = runLoop
        lock.unlock()
        ready.signal()
        CFRunLoopRun()
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let tap = self.tap
            lock.unlock()
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let code = UInt32(event.getIntegerValueField(.keyboardEventKeycode))
        let synthetic =
            event.getIntegerValueField(.eventSourceUserData) == PasteService.syntheticEventTag
        lock.lock()
        let route = HyperKeyRoute.route(
            type: type, code: code, flags: event.flags, synthetic: synthetic,
            hyper: hyperKeyCode, bindings: bindings, armed: &hyperDown)
        let actionMap = onAction
        lock.unlock()

        switch route {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .fire(let hotkeyID):
            if let actionMap {
                Task { @MainActor in actionMap(hotkeyID) }
            }
            return nil
        }
    }
}

/// What the macro-key tap does with one keyboard event. Pure, so the
/// arming rules are testable without a real event tap.
enum HyperKeyRoute: Equatable {
    case pass
    case swallow
    case fire(UInt32)

    static func route(
        type: CGEventType,
        code: UInt32,
        flags: CGEventFlags,
        synthetic: Bool,
        hyper: UInt32,
        bindings: [UInt32: UInt32],
        armed: inout Bool
    ) -> HyperKeyRoute {
        // The app's own ⌘V must reach the target app even while the layer is armed.
        if synthetic { return .pass }
        let hyperModifier = HotkeyBinding.modifierFlag(forKeyCode: hyper)
        if code == hyper {
            if hyper == UInt32(kVK_CapsLock) {
                // Caps Lock usually arrives as flagsChanged, not keyDown/keyUp.
                // Toggle a layer: press ⇪ to arm, press ⇪ again to disarm.
                if type == .flagsChanged { armed.toggle() }
                return .swallow
            }
            if hyperModifier != nil {
                // Modifiers only emit flagsChanged. Pass it on: other features
                // (the Right ⌥ dictation key) listen to the same modifier.
                if type == .flagsChanged {
                    armed = HotkeyBinding.eventReportsModifierDown(
                        keyCode: hyper,
                        flags: NSEvent.ModifierFlags(rawValue: UInt(flags.rawValue)))
                }
                return .pass
            }
            if type == .keyDown {
                armed = true
            } else if type == .keyUp {
                armed = false
            }
            return .swallow
        }

        guard armed, type == .keyDown, let hotkeyID = bindings[code] else { return .pass }
        // ⌘/⌃ shortcuts (⌘C, ⌃A) belong to the frontmost app, unless that
        // modifier is the macro key itself.
        var foreign: CGEventFlags = [.maskCommand, .maskControl]
        if hyperModifier == .command { foreign.remove(.maskCommand) }
        if hyperModifier == .control { foreign.remove(.maskControl) }
        guard flags.intersection(foreign).isEmpty else { return .pass }
        return .fire(hotkeyID)
    }
}
