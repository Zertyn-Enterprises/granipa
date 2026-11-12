import Carbon.HIToolbox
import SwiftUI

private enum ShortcutRecordTarget: Equatable {
    case extra(ExtraShortcut)
    case window(WindowAction)
}

struct ShortcutsSettings: View {
    @State private var hyperRaw = WindowHyperKey.current.rawValue
    @AppStorage("windowSnappingEnabled") private var snapping = true
    @State private var recording: ShortcutRecordTarget?
    @State private var captureMonitor: Any?
    @State private var stamp = 0

    private var hyper: WindowHyperKey {
        WindowHyperKey(rawValue: hyperRaw) ?? .off
    }

    var body: some View {
        Form {
            Section("Macro key") {
                Picker("Macro key", selection: $hyperRaw) {
                    ForEach(WindowHyperKey.allCases) { key in
                        Text(key.title).tag(key.rawValue)
                    }
                }
                .onChange(of: hyperRaw) {
                    WindowHyperKey.setCurrent(hyper)
                    ShortcutHub.shared.rebind()
                }
                Text(hyperHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Click a shortcut, then press the full chord (⌘→, ⌃⌥←, ⌥⇧V…). Esc cancels.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Hold to dictate stays on the Dictation tab — that key is independent so you can talk without arming the macro.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Productivity") {
                extraRow(.clipboard)
                extraRow(.ocr)
                extraRow(.emoji)
                extraRow(.history)
            }
            if snapping {
                Section("Windows") {
                    ForEach(
                        [
                            WindowAction.leftHalf, .rightHalf, .topHalf, .bottomHalf,
                            .maximize, .center, .restore,
                        ], id: \.self
                    ) { windowRow($0) }
                }
                Section("Quarters") {
                    ForEach(
                        [WindowAction.topLeft, .topRight, .bottomLeft, .bottomRight],
                        id: \.self
                    ) { windowRow($0) }
                }
                Section("Thirds") {
                    ForEach(
                        [WindowAction.firstThird, .centerThird, .lastThird],
                        id: \.self
                    ) { windowRow($0) }
                }
            }
            Button("Reset shortcuts") {
                WindowShortcuts.reset()
                hyperRaw = WindowHyperKey.off.rawValue
                stamp += 1
                ShortcutHub.shared.rebind()
            }
        }
        .formStyle(.grouped)
        .onDisappear { stopCapture() }
    }

    private var hyperHelp: String {
        switch hyper {
        case .off:
            "Each shortcut keeps its built-in modifiers (⌥⇧ for clipboard, ⌃⌥ for windows)."
        case .capsLock:
            "Press Caps Lock to arm, then any shortcut (⇪V clipboard, ⇪← left half). Press Caps Lock again to exit. Needs Accessibility."
        case .rightShift, .rightCommand, .rightOption:
            "Hold the macro key, then any shortcut. Other apps never see that chord. Needs Accessibility."
        }
    }

    private func extraRow(_ item: ExtraShortcut) -> some View {
        recorderRow(
            title: item.title,
            label: WindowShortcuts.chordLabel(for: item, hyper: hyper),
            target: .extra(item))
    }

    private func windowRow(_ action: WindowAction) -> some View {
        recorderRow(
            title: action.title,
            label: WindowShortcuts.chordLabel(for: action, hyper: hyper),
            target: .window(action))
    }

    private func recorderRow(title: String, label: String, target: ShortcutRecordTarget)
        -> some View
    {
        HStack {
            Text(title)
            Spacer()
            Button(recording == target ? "Press a key…" : label) {
                beginCapture(target)
            }
            .font(.system(.body, design: .monospaced))
        }
        .id("\(title)-\(stamp)-\(hyperRaw)")
    }

    private func beginCapture(_ target: ShortcutRecordTarget) {
        stopCapture()
        recording = target
        captureMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let code = UInt32(event.keyCode)
            if Int(event.keyCode) == kVK_Escape {
                stopCapture()
                return nil
            }
            if let hyperCode = hyper.keyCode, code == hyperCode {
                return nil
            }
            if HotkeyBinding.modifierFlag(forKeyCode: code) != nil {
                return nil
            }
            let mods = HotkeyBinding.carbonModifiers(from: event.modifierFlags)
            if hyper == .off, mods == 0 {
                return nil
            }
            switch target {
            case .extra(let item):
                ExtraShortcut.setChord(
                    keyCode: code,
                    modifiers: hyper == .off ? mods : item.fallbackModifiers,
                    for: item)
            case .window(let action):
                WindowShortcuts.setChord(
                    keyCode: code,
                    modifiers: hyper == .off ? mods : WindowShortcuts.defaultModifiers(for: action),
                    for: action)
            }
            stamp += 1
            ShortcutHub.shared.rebind()
            stopCapture()
            return nil
        }
    }

    private func stopCapture() {
        if let captureMonitor {
            NSEvent.removeMonitor(captureMonitor)
        }
        captureMonitor = nil
        recording = nil
    }
}
