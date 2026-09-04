import Carbon.HIToolbox
import Foundation

enum WindowHyperKey: String, CaseIterable, Identifiable, Sendable {
    case off
    case capsLock
    case rightShift
    case rightCommand
    case rightOption

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "None (built-in modifiers)"
        case .capsLock: "Caps Lock (Raycast-style)"
        case .rightShift: "Right Shift"
        case .rightCommand: "Right ⌘"
        case .rightOption: "Right ⌥"
        }
    }

    var keyCode: UInt32? {
        switch self {
        case .off: nil
        case .capsLock: UInt32(kVK_CapsLock)
        case .rightShift: UInt32(kVK_RightShift)
        case .rightCommand: UInt32(kVK_RightCommand)
        case .rightOption: UInt32(kVK_RightOption)
        }
    }

    var glyph: String {
        switch self {
        case .off: "⌃⌥"
        case .capsLock: "⇪"
        case .rightShift: "⇧"
        case .rightCommand: "⌘"
        case .rightOption: "⌥"
        }
    }

    static var current: WindowHyperKey {
        let raw =
            UserDefaults.standard.string(forKey: "globalMacroKey")
            ?? UserDefaults.standard.string(forKey: "windowHyperKey")
            ?? ""
        return WindowHyperKey(rawValue: raw) ?? .off
    }

    static func setCurrent(_ value: WindowHyperKey) {
        UserDefaults.standard.set(value.rawValue, forKey: "globalMacroKey")
    }
}

enum ExtraShortcut: String, CaseIterable, Identifiable, Sendable {
    case clipboard
    case ocr
    case emoji
    case history

    var id: String { rawValue }

    var hotkeyID: UInt32 {
        switch self {
        case .clipboard: 1
        case .ocr: 2
        case .emoji: 5
        case .history: 6
        }
    }

    var title: String {
        switch self {
        case .clipboard: "Clipboard history"
        case .ocr: "Capture screen text"
        case .emoji: "Emoji & Symbols"
        case .history: "Dictation history"
        }
    }

    var defaultKeyCode: UInt32 {
        switch self {
        case .clipboard: UInt32(kVK_ANSI_V)
        case .ocr: UInt32(kVK_ANSI_T)
        case .emoji: UInt32(kVK_ANSI_E)
        case .history: UInt32(kVK_ANSI_H)
        }
    }

    var fallbackModifiers: UInt32 { UInt32(optionKey | shiftKey) }

    static func defaultsKey(_ item: ExtraShortcut) -> String {
        "extraKey.\(item.rawValue)"
    }

    static func keyCode(for item: ExtraShortcut) -> UInt32 {
        if let stored = UserDefaults.standard.object(forKey: defaultsKey(item)) as? Int {
            return UInt32(stored)
        }
        return item.defaultKeyCode
    }

    static func setKeyCode(_ code: UInt32, for item: ExtraShortcut) {
        UserDefaults.standard.set(Int(code), forKey: defaultsKey(item))
    }

    static func modifiersKey(_ item: ExtraShortcut) -> String {
        "extraMods.\(item.rawValue)"
    }

    static func modifiers(for item: ExtraShortcut) -> UInt32 {
        if let stored = UserDefaults.standard.object(forKey: modifiersKey(item)) as? Int {
            return UInt32(stored)
        }
        return item.fallbackModifiers
    }

    static func setChord(keyCode: UInt32, modifiers: UInt32, for item: ExtraShortcut) {
        setKeyCode(keyCode, for: item)
        UserDefaults.standard.set(Int(modifiers), forKey: modifiersKey(item))
    }
}

enum WindowShortcuts {
    static func defaultsKey(for action: WindowAction) -> String {
        "windowKey.\(action.rawValue)"
    }

    static func defaultKeyCode(for action: WindowAction) -> UInt32 {
        switch action {
        case .leftHalf: UInt32(kVK_LeftArrow)
        case .rightHalf: UInt32(kVK_RightArrow)
        case .topHalf: UInt32(kVK_UpArrow)
        case .bottomHalf: UInt32(kVK_DownArrow)
        case .maximize: UInt32(kVK_Return)
        case .center: UInt32(kVK_ANSI_C)
        case .topLeft: UInt32(kVK_ANSI_U)
        case .topRight: UInt32(kVK_ANSI_I)
        case .bottomLeft: UInt32(kVK_ANSI_J)
        case .bottomRight: UInt32(kVK_ANSI_K)
        case .firstThird: UInt32(kVK_ANSI_D)
        case .centerThird: UInt32(kVK_ANSI_F)
        case .lastThird: UInt32(kVK_ANSI_G)
        case .restore: UInt32(kVK_Delete)
        }
    }

    static func keyCode(for action: WindowAction) -> UInt32 {
        if let stored = UserDefaults.standard.object(forKey: defaultsKey(for: action)) as? Int {
            return UInt32(stored)
        }
        return defaultKeyCode(for: action)
    }

    static func setKeyCode(_ code: UInt32, for action: WindowAction) {
        UserDefaults.standard.set(Int(code), forKey: defaultsKey(for: action))
    }

    static func modifiersKey(for action: WindowAction) -> String {
        "windowMods.\(action.rawValue)"
    }

    static func defaultModifiers(for action: WindowAction) -> UInt32 {
        UInt32(controlKey | optionKey)
    }

    static func modifiers(for action: WindowAction) -> UInt32 {
        if let stored = UserDefaults.standard.object(forKey: modifiersKey(for: action)) as? Int {
            return UInt32(stored)
        }
        return defaultModifiers(for: action)
    }

    static func setChord(keyCode: UInt32, modifiers: UInt32, for action: WindowAction) {
        setKeyCode(keyCode, for: action)
        UserDefaults.standard.set(Int(modifiers), forKey: modifiersKey(for: action))
    }

    static func reset() {
        for action in WindowAction.allCases {
            UserDefaults.standard.removeObject(forKey: defaultsKey(for: action))
            UserDefaults.standard.removeObject(forKey: modifiersKey(for: action))
        }
        for extra in ExtraShortcut.allCases {
            UserDefaults.standard.removeObject(forKey: ExtraShortcut.defaultsKey(extra))
            UserDefaults.standard.removeObject(forKey: ExtraShortcut.modifiersKey(extra))
        }
        setCurrentHyper(.off)
    }

    static func setCurrentHyper(_ value: WindowHyperKey) {
        WindowHyperKey.setCurrent(value)
    }

    static func keyName(_ code: UInt32) -> String {
        switch Int(code) {
        case Int(kVK_LeftArrow): "←"
        case Int(kVK_RightArrow): "→"
        case Int(kVK_UpArrow): "↑"
        case Int(kVK_DownArrow): "↓"
        case Int(kVK_Return): "⏎"
        case Int(kVK_Delete): "⌫"
        case Int(kVK_Space): "Space"
        case Int(kVK_Tab): "⇥"
        case Int(kVK_Escape): "Esc"
        case Int(kVK_ANSI_A): "A"
        case Int(kVK_ANSI_B): "B"
        case Int(kVK_ANSI_C): "C"
        case Int(kVK_ANSI_D): "D"
        case Int(kVK_ANSI_E): "E"
        case Int(kVK_ANSI_F): "F"
        case Int(kVK_ANSI_G): "G"
        case Int(kVK_ANSI_H): "H"
        case Int(kVK_ANSI_I): "I"
        case Int(kVK_ANSI_J): "J"
        case Int(kVK_ANSI_K): "K"
        case Int(kVK_ANSI_L): "L"
        case Int(kVK_ANSI_M): "M"
        case Int(kVK_ANSI_N): "N"
        case Int(kVK_ANSI_O): "O"
        case Int(kVK_ANSI_P): "P"
        case Int(kVK_ANSI_Q): "Q"
        case Int(kVK_ANSI_R): "R"
        case Int(kVK_ANSI_S): "S"
        case Int(kVK_ANSI_T): "T"
        case Int(kVK_ANSI_U): "U"
        case Int(kVK_ANSI_V): "V"
        case Int(kVK_ANSI_W): "W"
        case Int(kVK_ANSI_X): "X"
        case Int(kVK_ANSI_Y): "Y"
        case Int(kVK_ANSI_Z): "Z"
        case Int(kVK_ANSI_0): "0"
        case Int(kVK_ANSI_1): "1"
        case Int(kVK_ANSI_2): "2"
        case Int(kVK_ANSI_3): "3"
        case Int(kVK_ANSI_4): "4"
        case Int(kVK_ANSI_5): "5"
        case Int(kVK_ANSI_6): "6"
        case Int(kVK_ANSI_7): "7"
        case Int(kVK_ANSI_8): "8"
        case Int(kVK_ANSI_9): "9"
        default:
            "key \(code)"
        }
    }

    static func chordLabel(
        keyCode: UInt32, modifiers: UInt32, hyper: WindowHyperKey = .current
    ) -> String {
        let key = keyName(keyCode)
        if hyper == .off { return "\(HotkeyBinding.modifierGlyph(modifiers))\(key)" }
        return "\(hyper.glyph)\(key)"
    }

    static func chordLabel(for action: WindowAction, hyper: WindowHyperKey = .current) -> String {
        chordLabel(
            keyCode: keyCode(for: action), modifiers: modifiers(for: action), hyper: hyper)
    }

    static func chordLabel(for extra: ExtraShortcut, hyper: WindowHyperKey = .current) -> String {
        chordLabel(
            keyCode: ExtraShortcut.keyCode(for: extra),
            modifiers: ExtraShortcut.modifiers(for: extra),
            hyper: hyper)
    }
}
