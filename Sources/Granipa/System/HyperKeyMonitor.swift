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
    private var layer = HyperLayer(hyperKeyCode: 0, bindings: [:])
    private var onAction: (@MainActor (UInt32) -> Void)?

    @discardableResult
    func start(
        hyperKeyCode: UInt32,
        bindings: [UInt32: UInt32],
        onAction: @escaping @MainActor (UInt32) -> Void
    ) -> Bool {
        stop()
        lock.lock()
        self.layer = HyperLayer(hyperKeyCode: hyperKeyCode, bindings: bindings)
        self.onAction = onAction
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
            return false
        }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        lock.lock()
        self.tap = tap
        self.source = source
        lock.unlock()
        Self.log.info("hyper key monitor on code=\(hyperKeyCode)")
        return true
    }

    func stop() {
        lock.lock()
        let tap = self.tap
        let source = self.source
        self.tap = nil
        self.source = nil
        self.layer.release()
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
        let fromSelf =
            event.getIntegerValueField(.eventSourceUnixProcessID) == Int64(getpid())
        lock.lock()
        let outcome = layer.handle(code: code, type: type, fromSelf: fromSelf)
        let actionMap = onAction
        lock.unlock()

        switch outcome {
        case .pass:
            return Unmanaged.passUnretained(event)
        case .swallow:
            return nil
        case .action(let hotkeyID):
            if let actionMap {
                Task { @MainActor in actionMap(hotkeyID) }
            }
            return nil
        }
    }
}

/// Hold-to-use layer: while the macro key is down, bound keys fire their action
/// and are swallowed. Events this process posts itself (paste's ⌘V) always
/// pass, or a held layer would eat the paste and re-open the clipboard.
struct HyperLayer: Sendable {
    enum Outcome: Equatable {
        case pass, swallow
        case action(UInt32)
    }

    let hyperKeyCode: UInt32
    let bindings: [UInt32: UInt32]
    private(set) var isHeld = false

    init(hyperKeyCode: UInt32, bindings: [UInt32: UInt32]) {
        self.hyperKeyCode = hyperKeyCode
        self.bindings = bindings
    }

    mutating func release() { isHeld = false }

    mutating func handle(code: UInt32, type: CGEventType, fromSelf: Bool) -> Outcome {
        if fromSelf { return .pass }
        if code == hyperKeyCode {
            if type == .keyDown {
                isHeld = true
            } else if type == .keyUp {
                isHeld = false
            }
            return .swallow
        }
        guard isHeld, type == .keyDown, let id = bindings[code] else { return .pass }
        return .action(id)
    }
}
