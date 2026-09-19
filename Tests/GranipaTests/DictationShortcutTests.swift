import Carbon.HIToolbox
import Foundation
import Testing

@testable import Granipa

@Suite struct DictationShortcutTests {
    @Test @MainActor func shortcutLabelDefaultsToRightOption() {
        withDictationKeys(code: nil, modifiers: nil) {
            #expect(DictationController.shortcutLabel == "Right ⌥")
        }
    }

    @Test @MainActor func shortcutLabelRightCommand() {
        withDictationKeys(code: Int(kVK_RightCommand), modifiers: 0) {
            #expect(DictationController.shortcutLabel == "Right ⌘")
        }
    }

    @Test @MainActor func shortcutLabelOptionSpace() {
        withDictationKeys(code: Int(kVK_Space), modifiers: Int(optionKey)) {
            #expect(DictationController.shortcutLabel == "⌥ Space")
        }
    }
}

@MainActor
private func withDictationKeys(code: Int?, modifiers: Int?, _ body: () -> Void) {
    let defaults = UserDefaults.standard
    let previousCode = defaults.object(forKey: "dictationKeyCode")
    let previousModifiers = defaults.object(forKey: "dictationModifiers")
    defer {
        if let previousCode {
            defaults.set(previousCode, forKey: "dictationKeyCode")
        } else {
            defaults.removeObject(forKey: "dictationKeyCode")
        }
        if let previousModifiers {
            defaults.set(previousModifiers, forKey: "dictationModifiers")
        } else {
            defaults.removeObject(forKey: "dictationModifiers")
        }
    }
    if let code {
        defaults.set(code, forKey: "dictationKeyCode")
    } else {
        defaults.removeObject(forKey: "dictationKeyCode")
    }
    if let modifiers {
        defaults.set(modifiers, forKey: "dictationModifiers")
    } else {
        defaults.removeObject(forKey: "dictationModifiers")
    }
    body()
}
