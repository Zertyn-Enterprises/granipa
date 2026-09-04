import AppKit
import Carbon.HIToolbox
import CoreGraphics
import Foundation
import os

enum HotkeyBinding {
    /// Carbon `RegisterEventHotKey` never delivers modifier-only keys (Right Option,
    /// Right Command, …). Those need `flagsChanged`. Combos still use Carbon.
    static func modifierFlag(forKeyCode keyCode: UInt32) -> NSEvent.ModifierFlags? {
        switch Int(keyCode) {
        case Int(kVK_RightOption), Int(kVK_Option): .option
        case Int(kVK_RightCommand), Int(kVK_Command): .command
        case Int(kVK_RightControl), Int(kVK_Control): .control
        case Int(kVK_RightShift), Int(kVK_Shift): .shift
        default: nil
        }
    }

    static func isModifierOnly(keyCode: UInt32, modifiers: UInt32) -> Bool {
        modifiers == 0 && modifierFlag(forKeyCode: keyCode) != nil
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        let f = flags.intersection(.deviceIndependentFlagsMask)
        var carbon: UInt32 = 0
        if f.contains(.control) { carbon |= UInt32(controlKey) }
        if f.contains(.option) { carbon |= UInt32(optionKey) }
        if f.contains(.shift) { carbon |= UInt32(shiftKey) }
        if f.contains(.command) { carbon |= UInt32(cmdKey) }
        return carbon
    }

    static func modifierGlyph(_ carbon: UInt32) -> String {
        var glyph = ""
        if carbon & UInt32(controlKey) != 0 { glyph += "⌃" }
        if carbon & UInt32(optionKey) != 0 { glyph += "⌥" }
        if carbon & UInt32(shiftKey) != 0 { glyph += "⇧" }
        if carbon & UInt32(cmdKey) != 0 { glyph += "⌘" }
        return glyph
    }
}

// Carbon hotkeys need no Accessibility permission. Modifier-only holds (the
// default Right Option dictation key) cannot use Carbon; they use NSEvent
// flagsChanged, which needs Accessibility to see keys in other apps.
final class HotkeyManager: @unchecked Sendable {
    static let shared = HotkeyManager()
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "hotkey")

    private struct Handler {
        var onPress: @MainActor () -> Void
        var onRelease: (@MainActor () -> Void)?
    }

    private struct ModifierSpec {
        var keyCode: UInt32
    }

    private var handlers: [UInt32: Handler] = [:]
    private var hotkeyRefs: [UInt32: EventHotKeyRef] = [:]
    private var modifierSpecs: [UInt32: ModifierSpec] = [:]
    private var modifierDown: [UInt32: Bool] = [:]
    private var eventHandler: EventHandlerRef?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func register(
        id: UInt32, keyCode: UInt32, modifiers: UInt32, handler: @escaping @MainActor () -> Void
    ) {
        register(id: id, keyCode: keyCode, modifiers: modifiers, onPress: handler, onRelease: nil)
    }

    func register(
        id: UInt32,
        keyCode: UInt32,
        modifiers: UInt32,
        onPress: @escaping @MainActor () -> Void,
        onRelease: (@MainActor () -> Void)?
    ) {
        unregister(id: id)
        handlers[id] = Handler(onPress: onPress, onRelease: onRelease)
        if HotkeyBinding.isModifierOnly(keyCode: keyCode, modifiers: modifiers) {
            modifierSpecs[id] = ModifierSpec(keyCode: keyCode)
            modifierDown[id] = false
            refreshModifierMonitors()
            return
        }
        installIfNeeded()
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x47524E50), id: id)
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            Self.log.error("RegisterEventHotKey id=\(id) status=\(status)")
        }
        if let ref {
            hotkeyRefs[id] = ref
        }
    }

    func unregister(id: UInt32) {
        if let ref = hotkeyRefs.removeValue(forKey: id) {
            UnregisterEventHotKey(ref)
        }
        let hadModifier = modifierSpecs.removeValue(forKey: id) != nil
        modifierDown.removeValue(forKey: id)
        handlers.removeValue(forKey: id)
        if hadModifier {
            refreshModifierMonitors()
        }
    }

    private func refreshModifierMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        guard !modifierSpecs.isEmpty else { return }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }
        if globalMonitor == nil {
            Self.log.error("flagsChanged global monitor nil — grant Accessibility for Right Option dictation")
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let code = UInt32(event.keyCode)
        Task { @MainActor in
            self.dispatchModifier(code: code)
        }
    }

    @MainActor
    private func dispatchModifier(code: UInt32) {
        for (id, spec) in modifierSpecs where spec.keyCode == code {
            let down = CGEventSource.keyState(
                .combinedSessionState,
                key: CGKeyCode(code))
            let was = modifierDown[id] ?? false
            guard down != was else { continue }
            modifierDown[id] = down
            guard let handler = handlers[id] else { continue }
            if down {
                handler.onPress()
            } else {
                handler.onRelease?()
            }
        }
    }

    private func installIfNeeded() {
        guard eventHandler == nil else { return }
        var eventTypes = [
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID)
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                let id = hotKeyID.id
                let kind = GetEventKind(event)
                Task { @MainActor in
                    guard let handler = manager.handlers[id] else { return }
                    if kind == UInt32(kEventHotKeyReleased) {
                        handler.onRelease?()
                    } else {
                        handler.onPress()
                    }
                }
                return noErr
            },
            2,
            &eventTypes,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler)
    }
}
