import SwiftUI

struct ProductivitySettings: View {
    @Environment(AppState.self) private var app
    @AppStorage("clipboardHistoryEnabled") private var clipboardEnabled = true
    @AppStorage("autoPasteEnabled") private var autoPaste = true

    var body: some View {
        Form {
            Section("Clipboard history") {
                Toggle("Capture clipboard history", isOn: $clipboardEnabled)
                .onChange(of: clipboardEnabled) { app.setClipboardCaptureEnabled(clipboardEnabled) }
                Toggle("Paste automatically after selecting", isOn: $autoPaste)
                    .onChange(of: autoPaste) {
                        if autoPaste, !PasteService.isTrusted {
                            PasteService.requestTrust()
                        }
                    }
                Text("Sends ⌘V to the active app. Needs Accessibility permission.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Keeps the last 500 items locally. Skips items the source app marks as concealed or transient — check that your password manager sets that flag — and text over 1 MB or images over 20 MB.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear history", role: .destructive) {
                    if let db = app.database {
                        ClipboardMonitor.removeImageFiles((try? db.clearClipboardItems()) ?? [])
                    }
                }
            }
            Section("Text capture (OCR)") {
                Text("Recognized text lands in your clipboard. Needs Screen Recording on first use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Emoji & Symbols") {
                Text("Sends ⌃⌘Space to the front app (the system emoji picker). Needs Accessibility, same as auto-paste.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Keyboard shortcuts for these live in Settings → Shortcuts, including the global macro key.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

struct WindowSettings: View {
    @AppStorage("windowSnappingEnabled") private var snapping = true
    @State private var conflictingApp: String?

    var body: some View {
        Form {
            Toggle("Window snapping shortcuts", isOn: $snapping)
                .onChange(of: snapping) { WindowManager.shared.setEnabled(snapping) }
            Text("If a window is already parked on the left (or right), snapping another window that way fills the remaining space instead of covering it.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Keys and the global macro live in Settings → Shortcuts.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if WindowHyperKey.current == .off, let conflictingApp {
                Label(
                    "\(conflictingApp) is running and owns ⌃⌥. Set a macro key in Shortcuts, or quit that app.",
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            let knownConflicts = [
                "com.knollsoft.Rectangle": "Rectangle",
                "com.knollsoft.Hookshot": "Rectangle Pro",
                "com.divisiblebyzero.Spectacle": "Spectacle",
            ]
            conflictingApp = NSWorkspace.shared.runningApplications
                .compactMap { $0.bundleIdentifier.flatMap { knownConflicts[$0] } }
                .first
        }
    }
}
