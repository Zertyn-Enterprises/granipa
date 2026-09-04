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
    private var hyperKeyCode: UInt32 = 0
    private var bindings: [UInt32: UInt32] = [:]
    private var hyperDown = false
    private var onAction: (@MainActor (UInt32) -> Void)?

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return tap != nil
    }

    func start(
        hyperKeyCode: UInt32,
        bindings: [UInt32: UInt32],
        onAction: @escaping @MainActor (UInt32) -> Void
    ) {
        stop()
        lock.lock()
        self.hyperKeyCode = hyperKeyCode
        self.bindings = bindings
        self.onAction = onAction
        self.hyperDown = false
        lock.unlock()

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
            Self.log.error("CGEvent tap failed — grant Accessibility for the macro key")
            return
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.lock()
        self.tap = tap
        self.source = source
        lock.unlock()
        Self.log.info("hyper key monitor on code=\(hyperKeyCode)")
    }

    func stop() {
        lock.lock()
        let tap = self.tap
        let source = self.source
        self.tap = nil
        self.source = nil
        self.hyperDown = false
        lock.unlock()
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
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
        lock.lock()
        let hyper = hyperKeyCode
        let bindings = bindings
        let down = hyperDown
        let actionMap = onAction
        lock.unlock()

        if code == hyper {
            lock.lock()
            if hyper == UInt32(kVK_CapsLock) {
                // Caps Lock usually arrives as flagsChanged, not keyDown/keyUp.
                // Toggle a layer: press ⇪ to arm, press ⇪ again to disarm.
                if type == .flagsChanged { hyperDown.toggle() }
            } else if type == .keyDown {
                hyperDown = true
            } else if type == .keyUp {
                hyperDown = false
            }
            lock.unlock()
            return nil
        }

        if type == .flagsChanged {
            return Unmanaged.passUnretained(event)
        }

        guard down, type == .keyDown, let hotkeyID = bindings[code] else {
            return Unmanaged.passUnretained(event)
        }
        if let actionMap {
            Task { @MainActor in actionMap(hotkeyID) }
        }
        return nil
    }
}
