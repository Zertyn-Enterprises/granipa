import ServiceManagement
import Speech
import SwiftUI

struct GeneralSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage("defaultLocale") private var defaultLocale = "auto"
    @AppStorage("liveMeetingASR") private var liveMeetingASR = false
    @AppStorage("meetingCaptionsEnabled") private var meetingCaptions = true
    @AppStorage("meetingSystemEngine") private var meetingSystemEngine = "local"
    @AppStorage("meetingDetectionEnabled") private var meetingDetection = true
    @AppStorage("autoStopMode") private var autoStopMode = "ask"
    @AppStorage("audioRetentionDays") private var audioRetentionDays = 0
    @AppStorage("probeLocales") private var probeLocalesRaw = "en-US,es-ES"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var supportedLocales: [Locale] = []
    @State private var notificationsDenied = false

    private var probeSelection: [String] {
        probeLocalesRaw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        Form {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) {
                    do {
                        if launchAtLogin {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin = SMAppService.mainApp.status == .enabled
                    }
                }
            Picker("Meeting language", selection: $defaultLocale) {
                Text("Automatic detection").tag("auto")
                ForEach(supportedLocales, id: \.identifier) { locale in
                    let id = locale.identifier(.bcp47)
                    Text(LanguageDetection.displayName(id)).tag(id)
                }
            }
            if defaultLocale == "auto" {
                Section("Languages to detect (up to \(LanguageDetection.maxProbeLocales))") {
                    if supportedLocales.isEmpty {
                        Text("Loading available languages…")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(supportedLocales, id: \.identifier) { locale in
                        let id = locale.identifier(.bcp47)
                        Toggle(LanguageDetection.displayName(id), isOn: probeBinding(id))
                            .disabled(
                                !LanguageDetection.probeIncludesLanguage(probeSelection, of: id)
                                    && probeSelection.count >= LanguageDetection.maxProbeLocales)
                    }
                    Text("Each recording probes these languages for the first seconds and keeps the best match. Each language downloads its on-device model once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Live transcription during meetings", isOn: $liveMeetingASR)
                .onChange(of: liveMeetingASR) { syncLiveCaptionsOverlay() }
            Text("Streams speech while you record. Uses significant CPU and applies from the next recording. Off by default — meetings still transcribe after you stop.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Live captions during meetings", isOn: $meetingCaptions)
                .disabled(!liveMeetingASR)
                .onChange(of: meetingCaptions) { syncLiveCaptionsOverlay() }
            Text(
                liveMeetingASR
                    ? "Floating overlay of what's being said. Stays on this Mac."
                    : "Needs live transcription. The overlay has nothing to show until then."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Picker("Them (computer audio)", selection: $meetingSystemEngine) {
                Text("On-device (Apple)").tag("local")
                Text("Muse (computer audio only)").tag("muse")
            }
            .disabled(!liveMeetingASR)
            Text(computerAudioHelp)
            .font(.caption)
            .foregroundStyle(.secondary)
            if meetingSystemEngine == "muse", !KeychainStore.hasMuseKey() {
                Label(
                    "No Muse API key saved, so meetings transcribe computer audio on this Mac. Add the key in Settings → Dictation → Muse.",
                    systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Toggle("Detect meetings automatically", isOn: $meetingDetection)
                .onChange(of: meetingDetection) {
                    meetingDetection ? app.detector.start() : app.detector.stop()
                }
            if meetingDetection, notificationsDenied {
                Label(
                    "Notifications are off, so detection only shows a banner inside Grañipa. Enable them in System Settings → Notifications → Grañipa.",
                    systemImage: "bell.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            Picker("When the meeting app hangs up", selection: $autoStopMode) {
                Text("Do nothing").tag("off")
                Text("Ask to stop recording").tag("ask")
                Text("Stop recording automatically").tag("auto")
            }
            .disabled(!meetingDetection)
            if !meetingDetection {
                Text("Needs meeting detection: without it Grañipa cannot tell when the meeting app hangs up.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Picker("Keep meeting audio files", selection: $audioRetentionDays) {
                Text("Forever").tag(0)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
            }
            Text("Transcripts and notes are always kept; this only removes the m4a recordings (~30 MB per hour).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .task {
            notificationsDenied = await NotificationManager.authorizationDenied()
            let locales = await SpeechTranscriber.supportedLocales
            supportedLocales = dedupeByLanguage(locales).sorted {
                LanguageDetection.displayName($0.identifier(.bcp47))
                    < LanguageDetection.displayName($1.identifier(.bcp47))
            }
        }
    }

    private var computerAudioHelp: String {
        if !liveMeetingASR {
            return "Computer-audio engine applies only while live transcription is on. After Stop, both channels transcribe on this Mac."
        }
        return meetingSystemEngine == "muse"
            ? "Only the other participants' audio is sent to Meta. Your microphone stays on this Mac. Needs a Muse API key in Settings → Dictation."
            : "Both channels transcribe on this Mac."
    }

    private func syncLiveCaptionsOverlay() {
        CaptionsOverlayController.shared.setVisible(app.recorder.isRecording)
    }

    // One entry per language; regional variants are an implementation detail.
    private func dedupeByLanguage(_ locales: [Locale]) -> [Locale] {
        let preferredRegion: [String: String] = [
            "en": "US", "es": "ES", "zh": "CN", "yue": "CN", "pt": "BR",
            "fr": "FR", "de": "DE", "it": "IT", "ja": "JP", "ko": "KR", "ar": "SA",
        ]
        var byLanguage: [String: [Locale]] = [:]
        for locale in locales {
            let code = locale.language.languageCode?.identifier ?? locale.identifier
            byLanguage[code, default: []].append(locale)
        }
        let currentRegion = Locale.current.region?.identifier
        return byLanguage.map { code, variants in
            if let match = variants.first(where: { $0.region?.identifier == currentRegion }) {
                return match
            }
            if let preferred = preferredRegion[code],
                let match = variants.first(where: { $0.region?.identifier == preferred })
            {
                return match
            }
            return variants.sorted { $0.identifier < $1.identifier }[0]
        }
    }

    private func probeBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { LanguageDetection.probeIncludesLanguage(probeSelection, of: id) },
            set: { enabled in
                let selection = LanguageDetection.toggleProbeLanguage(
                    probeSelection, localeID: id, enabled: enabled)
                if !selection.isEmpty {
                    probeLocalesRaw = selection.joined(separator: ",")
                }
            })
    }
}
