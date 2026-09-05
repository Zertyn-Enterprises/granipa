import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        captureSection
        Divider()
        toolsSection
        Divider()
        appSection
        if BatteryService.shared.snapshot.isPresent {
            Divider()
            Menu("Battery") {
                BatteryMenuSection()
            }
        }
        Divider()
        Button("Quit Grañipa") {
            NSApp.terminate(nil)
        }
    }

    @ViewBuilder
    private var captureSection: some View {
        switch app.dictation.phase {
        case .preparing, .listening:
            Button {
                app.dictation.toggleFromMenu()
            } label: {
                Label("Stop Dictation", systemImage: "mic.fill")
            }
        case .processing:
            Text("Transcribing…")
        default:
            Button {
                app.dictation.toggleFromMenu()
            } label: {
                Label("Dictate", systemImage: "mic")
            }
            .disabled(app.recorder.isBusy)
        }

        if app.recorder.isBusy {
            Button {
                Task { await app.stopRecording() }
            } label: {
                Label(
                    app.recorder.isStarting ? "Cancel Recording Start" : "Stop Recording",
                    systemImage: app.recorder.isStarting ? "xmark.circle" : "stop.circle")
            }
            if app.recorder.isRecording {
                Button {
                    openWindow(id: "recording-hud")
                } label: {
                    Label("Show Recording HUD", systemImage: "rectangle.inset.filled")
                }
                if app.transcription != nil, MeetingASRPolicy.usesLiveCaptions() {
                    if CaptionsOverlayController.shared.dismissedThisRecording {
                        Button {
                            CaptionsOverlayController.shared.resetDismissed()
                            CaptionsOverlayController.shared.setVisible(true)
                        } label: {
                            Label("Show Captions", systemImage: "captions.bubble")
                        }
                    } else {
                        Button {
                            CaptionsOverlayController.shared.hideTemporarily()
                        } label: {
                            Label("Hide Captions", systemImage: "captions.bubble.fill")
                        }
                    }
                }
                if case .failed = app.transcription?.phase {
                    Text("Transcription failed")
                }
            }
        } else {
            Button {
                app.startRecording()
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Record New Meeting", systemImage: "record.circle")
            }
        }

        if !app.recorder.isBusy,
            app.processingMeetingID != nil || !app.enhancingMeetingIDs.isEmpty
        {
            Text("Processing notes…")
        }

        Button {
            app.createMeeting()
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Quick note", systemImage: "plus")
        }
    }

    @ViewBuilder
    private var toolsSection: some View {
        Button {
            ClipboardPanelController.shared.toggle()
        } label: {
            Label("Clipboard History", systemImage: "doc.on.clipboard")
        }
        .keyboardShortcut("v", modifiers: [.option, .shift])
        Button {
            Task { await OCRService.captureAndCopy() }
        } label: {
            Label("Capture Text (OCR)", systemImage: "text.viewfinder")
        }
        .keyboardShortcut("t", modifiers: [.option, .shift])
        Button {
            EmojiPalette.show()
        } label: {
            Label("Emoji & Symbols", systemImage: "face.smiling")
        }
        .keyboardShortcut("e", modifiers: [.option, .shift])
        Button {
            DictationHistoryPanelController.shared.toggle()
        } label: {
            Label("Dictation History", systemImage: "clock")
        }
        .keyboardShortcut("h", modifiers: [.option, .shift])
    }

    @ViewBuilder
    private var appSection: some View {
        Button {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Open Grañipa", systemImage: "macwindow")
        }
        SettingsLink {
            Label("Settings", systemImage: "gearshape")
        }
        Button {
            openWindow(id: "onboarding")
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            Label("Setup Guide…", systemImage: "questionmark.circle")
        }
        if UpdaterManager.shared.isAvailable {
            Button {
                UpdaterManager.shared.checkForUpdates()
            } label: {
                Label("Check for Updates…", systemImage: "arrow.triangle.2.circlepath")
            }
        }
    }
}

enum BatteryMenuHeadline {
    static func text(for snap: BatterySnapshot) -> String {
        if let minutes = snap.minutesToEmpty, minutes > 0, !snap.isCharging {
            return "\(snap.percent)% · \(snap.menuBarText)"
        }
        if snap.isCharging {
            return "\(snap.percent)% charging"
        }
        return "\(snap.percent)%"
    }
}

private struct BatteryMenuSection: View {
    var body: some View {
        @Bindable var battery = BatteryService.shared
        let snap = battery.snapshot
        Text(BatteryMenuHeadline.text(for: snap))
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
