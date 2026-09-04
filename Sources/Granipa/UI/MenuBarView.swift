import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow

    private var livePipeline: MeetingPipelinePhase? {
        app.meetings.lazy.map { app.pipelinePhase(for: $0) }
            .first { $0.isLive && $0 != .recording }
    }

    var body: some View {
        if BatteryService.shared.snapshot.isPresent {
            BatteryMenuSection()
            Divider()
        }
        // Capture
        if app.dictation.phase.isActive {
            Button("Stop Dictation") {
                app.dictation.toggleFromMenu()
            }
        } else {
            Button("Dictate") {
                app.dictation.toggleFromMenu()
            }
        }
        if app.recorder.isBusy {
            Button(app.recorder.isStarting ? "Cancel Recording Start" : "Stop Recording") {
                Task { await app.stopRecording() }
            }
            if app.recorder.isRecording {
                Button("Show Recording HUD") {
                    openWindow(id: "recording-hud")
                }
                if CaptionsOverlayController.shared.dismissedThisRecording {
                    Button("Show Captions") {
                        CaptionsOverlayController.shared.resetDismissed()
                        CaptionsOverlayController.shared.setVisible(true)
                    }
                } else {
                    Button("Hide Captions") {
                        CaptionsOverlayController.shared.hideTemporarily()
                    }
                }
            }
        } else {
            Button("Record New Meeting") {
                app.startRecording()
                NSApp.activate(ignoringOtherApps: true)
            }
            .disabled(app.recorder.isStarting)
        }
        if let phase = livePipeline {
            Button("\(phase.label) notes…") {}
                .disabled(true)
        }
        Button("New Meeting") {
            app.createMeeting()
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        // Tools
        Button("Clipboard History") {
            ClipboardPanelController.shared.toggle()
        }
        .keyboardShortcut("v", modifiers: [.option, .shift])
        Button("Capture Text (OCR)") {
            Task { await OCRService.captureAndCopy() }
        }
        .keyboardShortcut("t", modifiers: [.option, .shift])
        Button("Emoji & Symbols") {
            EmojiPalette.show()
        }
        .keyboardShortcut("e", modifiers: [.option, .shift])
        Button("Dictation History") {
            DictationHistoryPanelController.shared.toggle()
        }
        .keyboardShortcut("h", modifiers: [.option, .shift])
        Divider()
        // App
        Button("Open Grañipa") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Button("Setup Guide…") {
            openWindow(id: "onboarding")
            NSApp.activate(ignoringOtherApps: true)
        }
        if UpdaterManager.shared.isAvailable {
            Button("Check for Updates…") {
                UpdaterManager.shared.checkForUpdates()
            }
        }
        Divider()
        Button("Quit Grañipa") {
            NSApp.terminate(nil)
        }
    }
}

private struct BatteryMenuSection: View {
    var body: some View {
        @Bindable var battery = BatteryService.shared
        let snap = battery.snapshot
        Text("\(snap.percent)% · \(snap.menuBarText)")
            .foregroundStyle(.secondary)
        Toggle("Charge limit", isOn: $battery.limiterEnabled)
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
            Text("Limit: \(battery.limit)%")
                .foregroundStyle(.secondary)
            Button(battery.discharging ? "Stop discharge" : "Discharge") {
                if battery.discharging {
                    battery.discharging = false
                    battery.tick()
                } else {
                    battery.beginDischarge()
                }
            }
            Button(battery.topUp ? "Stop top up" : "Top Up") {
                if battery.topUp {
                    battery.topUp = false
                    battery.tick()
                } else {
                    battery.beginTopUp()
                }
            }
        }
        Toggle("Heat Protection", isOn: $battery.heatProtection)
            .disabled(battery.isCalibrating)
        if battery.isCalibrating {
            Text("Calibrating: \(battery.calibrationStep?.title ?? "")")
                .foregroundStyle(.secondary)
            Button("Stop Calibration") { battery.stopCalibration() }
        } else {
            Button("Start Calibration") { battery.startCalibration() }
                .disabled(!battery.canControl)
        }
        if battery.hasMagSafeLED {
            Picker("MagSafe LED", selection: $battery.magSafeLED) {
                ForEach(MagSafeLEDMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
        }
        if battery.canControl {
            Button(
                battery.helperEnabled
                    ? "Reinstall battery helper…" : "Install battery helper…"
            ) {
                battery.installHelper()
            }
        }
        if let message = battery.controlMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(4)
        }
    }
}
