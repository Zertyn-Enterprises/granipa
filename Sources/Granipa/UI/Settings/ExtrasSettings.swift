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

struct BatterySettings: View {
    var body: some View {
        @Bindable var battery = BatteryService.shared
        let helperHealthy = battery.helperHealthy
        Form {
            if !battery.snapshot.isPresent {
                Text("No internal battery — charge limiting is for MacBooks.")
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    "Experimental. Charge control writes to the battery controller through a root helper; these controls stay off until the helper works.",
                    systemImage: "flask")
                    .font(.caption)
                    .foregroundStyle(.orange)
                LabeledContent("Current charge", value: "\(battery.snapshot.percent)%")
                if let temp = battery.temperatureC {
                    LabeledContent("Battery temperature", value: String(format: "%.1f°C", temp))
                }
                // Turning a control off stays possible so a broken helper never
                // traps the Mac in a limited state.
                Toggle("Limit charging", isOn: $battery.limiterEnabled)
                    .disabled(battery.isCalibrating || (!helperHealthy && !battery.limiterEnabled))
                if battery.limiterEnabled {
                    Slider(
                        value: Binding(
                            get: { Double(battery.limit) },
                            set: { battery.limit = Int($0) }),
                        in: Double(ChargePolicy.minLimit)...Double(ChargePolicy.maxLimit),
                        step: 5,
                        onEditingChanged: { editing in
                            if !editing { battery.tick() }
                        })
                    .disabled(!helperHealthy)
                    Text("Stop charging at \(battery.limit)%. To come down from a higher level or charge to 100% once, use Discharge or Top Up in the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if battery.canControl {
                    Section("Battery helper") {
                        LabeledContent(
                            "Status",
                            value: battery.helperEnabled ? "Registered" : "Not registered")
                        Text(
                            "Registration reflects macOS Login Items state; it does not confirm the helper is running."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        if let message = battery.helperSetupMessage ?? battery.controlMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        if battery.helperSetupMessage != nil {
                            Button("Open Login Items…") {
                                battery.openHelperApproval()
                            }
                        }
                        Button(
                            battery.helperEnabled
                                ? "Repair battery helper…" : "Install battery helper…"
                        ) {
                            Task { await battery.repairHelper() }
                        }
                        .disabled(battery.helperBusy)
                        Text(
                            "Charge-limit writes need a root helper. After installing, approve Grañipa in System Settings → General → Login Items."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Heat Protection") {
                    Toggle("Heat Protection", isOn: $battery.heatProtection)
                        .disabled(
                            battery.isCalibrating || (!helperHealthy && !battery.heatProtection))
                    if battery.heatProtection {
                        Stepper(
                            "Halt charging at \(battery.heatThresholdC)°C",
                            value: $battery.heatThresholdC, in: 30...45)
                        .disabled(!helperHealthy)
                        Text("Recommended 35°C. Disabled automatically during calibration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Calibration Mode") {
                    Text("Charge to 100% → discharge to 10% → charge to 100% → hold 1h → discharge to 75%. Recalibrates the battery gauge. Leave the Mac plugged in.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        ForEach(CalibrationStep.allCases) { step in
                            Text(step.title)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(
                                    battery.calibrationStep == step
                                        ? Theme.accent : Theme.textTertiary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    if battery.isCalibrating {
                        Button("Stop Calibration", role: .destructive) {
                            battery.stopCalibration()
                        }
                    } else {
                        Button("Start Calibration") {
                            battery.startCalibration()
                        }
                        .disabled(!helperHealthy)
                    }
                    LabeledContent("Last calibration") {
                        if let date = battery.lastCalibrationAt {
                            Text(date, format: .dateTime.month().day().hour().minute())
                        } else {
                            Text("—")
                        }
                    }
                }

                if battery.hasMagSafeLED {
                    Section("MagSafe LED") {
                        Picker("LED setting", selection: $battery.magSafeLED) {
                            ForEach(MagSafeLEDMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .disabled(!helperHealthy)
                    }
                }

                if !battery.canControl, let message = battery.controlMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Text("On quit, Grañipa re-enables charging and returns the MagSafe LED to System. macOS 26 also has a system charge limit in System Settings → Battery; the lower of the two wins.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
