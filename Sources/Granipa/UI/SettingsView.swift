import Carbon.HIToolbox
import ServiceManagement
import Speech
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            DictationSettings()
                .tabItem { Label("Dictation", systemImage: "mic") }
            ShortcutsSettings()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            PermissionsSettings()
                .tabItem { Label("Permissions", systemImage: "lock.shield") }
            AITab()
                .tabItem { Label("AI", systemImage: "wand.and.stars") }
            ExtrasTab()
                .tabItem { Label("Extras", systemImage: "puzzlepiece") }
            IntegrationsTab()
                .tabItem { Label("Integrations", systemImage: "network") }
        }
        .frame(width: 640, height: 600)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
    }
}

private struct AITab: View {
    @State private var pane = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) {
                Text("Providers").tag(0)
                Text("Templates").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            if pane == 0 {
                AISettings()
            } else {
                TemplateSettings()
            }
        }
    }
}

private struct ExtrasTab: View {
    @State private var pane = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) {
                Text("Clipboard & OCR").tag(0)
                Text("Windows").tag(1)
                Text("Battery").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            if pane == 0 {
                ProductivitySettings()
            } else if pane == 1 {
                WindowSettings()
            } else {
                BatterySettings()
            }
        }
    }
}

private struct IntegrationsTab: View {
    @State private var pane = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $pane) {
                Text("API").tag(0)
                Text("Webhooks").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(10)
            if pane == 0 {
                APISettings()
            } else {
                WebhookSettings()
            }
        }
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage("defaultLocale") private var defaultLocale = "auto"
    @AppStorage("echoCancellation") private var echoCancellation = true
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
                    Text(languageName(id)).tag(id)
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
                        Toggle(languageName(id), isOn: probeBinding(id))
                            .disabled(
                                !probeSelection.contains(id)
                                    && probeSelection.count >= LanguageDetection.maxProbeLocales)
                    }
                    Text("Each recording probes these languages for the first seconds and keeps the best match. Each language downloads its on-device model once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Live captions during meetings", isOn: $meetingCaptions)
            Text("Floating overlay of what's being said. Stays on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Them (computer audio)", selection: $meetingSystemEngine) {
                Text("On-device (Apple)").tag("local")
                Text("Muse (computer audio only)").tag("muse")
            }
            Text(
                meetingSystemEngine == "muse"
                    ? "Only the other participants' audio is sent to Meta. Your microphone stays on this Mac. Needs a Muse API key in Settings → Dictation."
                    : "Both channels transcribe on this Mac."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
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
            Picker("Keep meeting audio files", selection: $audioRetentionDays) {
                Text("Forever").tag(0)
                Text("7 days").tag(7)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
            }
            Text("Transcripts and notes are always kept; this only removes the m4a recordings (~30 MB per hour).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Echo cancellation (mic)", isOn: $echoCancellation)
            Text("Stops other participants' voices from bleeding into your mic channel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .task {
            notificationsDenied = await NotificationManager.authorizationDenied()
            let locales = await SpeechTranscriber.supportedLocales
            supportedLocales = dedupeByLanguage(locales).sorted {
                languageName($0.identifier(.bcp47)) < languageName($1.identifier(.bcp47))
            }
        }
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
            get: { probeSelection.contains(id) },
            set: { enabled in
                var selection = probeSelection
                if enabled {
                    if !selection.contains(id),
                        selection.count < LanguageDetection.maxProbeLocales
                    {
                        selection.append(id)
                    }
                } else {
                    selection.removeAll { $0 == id }
                }
                if !selection.isEmpty {
                    probeLocalesRaw = selection.joined(separator: ",")
                }
            })
    }

    private func languageName(_ id: String) -> String {
        let locale = Locale(identifier: id)
        if let code = locale.language.languageCode?.identifier,
            let name = Locale.current.localizedString(forLanguageCode: code)
        {
            return name.capitalized
        }
        return Locale.current.localizedString(forIdentifier: id)?.capitalized ?? id
    }
}

private struct DictationSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage("dictationEngine") private var engine = "local"
    @AppStorage("dictationAutoPaste") private var autoPaste = true
    @AppStorage("dictationKeywords") private var keywords = ""
    @AppStorage("dictationShortcut") private var shortcut = "rightOption"
    @AppStorage("dictationLocale") private var dictationLocale = "auto"
    @AppStorage("probeLocales") private var probeLocalesRaw = "en-US,es-ES"
    @AppStorage("dictationRewrite") private var rewrite = "off"
    @AppStorage("rewriteCustomURL") private var rewriteURL = "http://127.0.0.1:11434/v1"
    @AppStorage("rewriteCustomModel") private var rewriteModel = "llama3.2"
    @State private var museKey = ""
    @State private var keySaved: Bool?
    @State private var spaceXAIKey = ""
    @State private var spaceXAIKeySaved: Bool?
    @State private var customKey = ""
    @State private var customKeySaved: Bool?

    private var probeIDs: [String] {
        LanguageDetection.parseProbeLocales(probeLocalesRaw)
    }

    var body: some View {
        ScrollView {
        Form {
            Section("Shortcut") {
                Picker("Hold to dictate", selection: $shortcut) {
                    Text("Right Option (⌥)").tag("rightOption")
                    Text("Right Command (⌘)").tag("rightCommand")
                    Text("Option + Space").tag("optionSpace")
                }
                .onChange(of: shortcut) { applyShortcut(); app.registerDictationHotkey() }
                Text("Hold to talk, release to paste. A quick tap toggles; press again to stop. Esc cancels only while you hold, not in toggle. Right Option and Right Command need Accessibility (same grant as auto-paste) so they work in other apps. Option+Space uses a Carbon hotkey and does not.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Every dictation is saved locally. Open history from the sidebar, the menu bar, or the shortcut in Settings → Shortcuts — stats (WPM, words, apps, time saved) live at the top.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Language") {
                Picker("Dictation language", selection: $dictationLocale) {
                    Text("Auto (last meeting / this Mac)").tag("auto")
                    ForEach(probeIDs, id: \.self) { id in
                        Text(id).tag(id)
                    }
                }
                Text("Meetings still probe languages. Dictation uses one model so it stays fast.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Engine") {
                Picker("Transcription engine", selection: $engine) {
                    Text("On-device (Apple)").tag("local")
                    Text("Muse Voice Transcribe").tag("muse")
                }
                Text(
                    engine == "local"
                        ? "Your voice stays on this Mac. This is the default for dictation."
                        : "Sends YOUR microphone to Meta. For meetings, prefer Settings → General → Them (computer audio only)."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if engine == "muse" {
                Section("Muse") {
                    SecureField("Meta API key", text: $museKey)
                    Button("Save key") {
                        keySaved = KeychainStore.set(
                            museKey, account: KeychainStore.museAPIKeyAccount)
                    }
                    if keySaved == false {
                        Text("Could not save the key in Keychain.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if keySaved == true {
                        Text("Saved in Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Audio is sent with zero-data-retention requested. $0.18/hour.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Vocabulary hints (comma-separated)", text: $keywords)
                    Text("Names, products, jargon Muse should prefer.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Paste into the front app", isOn: $autoPaste)
                .onChange(of: autoPaste) {
                    if autoPaste, !PasteService.isTrusted {
                        PasteService.requestTrust()
                    }
                }
            Text("Needs Accessibility permission. If it's off, dictation still copies the text.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Section("Instant rewrite") {
                Picker("After dictation", selection: $rewrite) {
                    Text("Off — paste what I said").tag("off")
                    Text("SpaceXAI (Grok)").tag("spacexai")
                    Text("Custom (Mac Mini / VPS)").tag("custom")
                }
                Text("Cleans punctuation and obvious ASR mistakes, then pastes. Your mic audio never goes to the rewrite API — only the text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if rewrite == "spacexai" {
                    SecureField("SpaceXAI API key", text: $spaceXAIKey)
                    Button("Save SpaceXAI key") {
                        spaceXAIKeySaved = KeychainStore.set(
                            spaceXAIKey, account: KeychainStore.spaceXAIKeyAccount)
                    }
                    if spaceXAIKeySaved == false {
                        Text("Could not save the key in Keychain.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    Text("Uses grok-4.6 at api.x.ai. Get a key at console.x.ai.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if rewrite == "custom" {
                    TextField("Base URL", text: $rewriteURL)
                    TextField("Model", text: $rewriteModel)
                    SecureField("API key (optional)", text: $customKey)
                    Button("Save endpoint key") {
                        customKeySaved = KeychainStore.set(
                            customKey, account: KeychainStore.rewriteCustomKeyAccount)
                    }
                    Text("OpenAI-compatible /v1/chat/completions. Example: Ollama or llama.cpp on your Mac Mini (http://192.168.x.x:11434/v1), or a VPS.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        }
        .onAppear {
            museKey = KeychainStore.get(account: KeychainStore.museAPIKeyAccount) ?? ""
            spaceXAIKey = KeychainStore.get(account: KeychainStore.spaceXAIKeyAccount) ?? ""
            customKey = KeychainStore.get(account: KeychainStore.rewriteCustomKeyAccount) ?? ""
            applyShortcut()
        }
    }

    private func applyShortcut() {
        switch shortcut {
        case "rightCommand":
            UserDefaults.standard.set(Int(kVK_RightCommand), forKey: "dictationKeyCode")
            UserDefaults.standard.set(0, forKey: "dictationModifiers")
        case "optionSpace":
            UserDefaults.standard.set(Int(kVK_Space), forKey: "dictationKeyCode")
            UserDefaults.standard.set(Int(optionKey), forKey: "dictationModifiers")
        default:
            UserDefaults.standard.set(Int(kVK_RightOption), forKey: "dictationKeyCode")
            UserDefaults.standard.set(0, forKey: "dictationModifiers")
        }
    }
}

private struct AISettings: View {
    @AppStorage("llmProvider") private var llmProvider = "claude"
    @AppStorage("diarizationEnabled") private var diarizationEnabled = true
    @AppStorage("inferSpeakerNames") private var inferSpeakerNames = true

    var body: some View {
        Form {
            Picker("Notes provider", selection: $llmProvider) {
                ForEach(LLMProviders.all) { spec in
                    Text(spec.displayName).tag(spec.id)
                }
            }
            Text("Uses the CLI's own subscription login — no API keys, no per-token billing.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Section("Speakers") {
                Toggle("Identify individual speakers", isOn: $diarizationEnabled)
                Text("Splits remote participants into Speaker 1, 2, 3… after the meeting (local CoreML model, ~20 MB downloaded on first use).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Infer speaker names with AI", isOn: $inferSpeakerNames)
                    .disabled(!diarizationEnabled)
            }

            Section("Providers") {
                ForEach(LLMProviders.all) { spec in
                    ProviderRow(spec: spec)
                }
                Text("Sign-in happens in each provider's CLI (one-time browser login). Grañipa never sees your credentials.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ProviderRow: View {
    let spec: LLMProviderSpec
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle, running, ok
        case failed(String)
    }

    private var installedPath: String? {
        LLMProviders.resolveExecutable(named: spec.executableName)?.path
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Image(systemName: installedPath != nil ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(installedPath != nil ? .green : .secondary)
                Text(spec.displayName)
                Spacer()
                if installedPath != nil {
                    switch testState {
                    case .idle:
                        Button("Test") { runTest() }
                            .controlSize(.small)
                    case .running:
                        ProgressView()
                            .controlSize(.small)
                    case .ok:
                        Label("Working", systemImage: "checkmark.seal.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    case .failed:
                        Button("Retry") { runTest() }
                            .controlSize(.small)
                    }
                }
            }
            if installedPath == nil {
                if let install = spec.installCommand {
                    HStack(spacing: 6) {
                        Text(install)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(install, forType: .string)
                            ToastController.shared.show("Install command copied")
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                    }
                }
                Text(spec.loginHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if case .failed(let message) = testState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.orange)
                Button("Open Terminal to sign in") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(spec.executableName, forType: .string)
                    NSWorkspace.shared.open(
                        URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                    ToastController.shared.show("Command copied — paste it in Terminal")
                }
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private func runTest() {
        testState = .running
        Task {
            do {
                _ = try await LLMService.generate(
                    providerID: spec.id, prompt: "Reply with exactly: OK", timeout: 120)
                testState = .ok
            } catch {
                let raw = error.localizedDescription
                let lower = raw.lowercased()
                let authHint =
                    lower.contains("login") || lower.contains("auth")
                    || lower.contains("credential") || lower.contains("api key")
                let prefix = authHint ? "Not signed in. \(spec.loginHint) " : ""
                testState = .failed(prefix + String(raw.prefix(160)))
            }
        }
    }
}

private struct ProductivitySettings: View {
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
                Text("Keeps the last 500 items locally. Password-manager entries are never captured.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Clear history", role: .destructive) {
                    if let db = app.database {
                        let paths = (try? db.clearClipboardItems()) ?? []
                        for path in paths {
                            try? FileManager.default.removeItem(atPath: path)
                        }
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

private enum ShortcutRecordTarget: Equatable {
    case extra(ExtraShortcut)
    case window(WindowAction)
}

private struct ShortcutsSettings: View {
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

private struct WindowSettings: View {
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

private struct BatterySettings: View {
    var body: some View {
        @Bindable var battery = BatteryService.shared
        Form {
            if !battery.snapshot.isPresent {
                Text("No internal battery — charge limiting is for MacBooks.")
                    .foregroundStyle(.secondary)
            } else {
                LabeledContent("Current charge", value: "\(battery.snapshot.percent)%")
                if let temp = battery.temperatureC {
                    LabeledContent("Battery temperature", value: String(format: "%.1f°C", temp))
                }
                Toggle("Limit charging", isOn: $battery.limiterEnabled)
                    .disabled(battery.isCalibrating)
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
                    Text("Stop charging at \(battery.limit)%. Discharge while plugged in to come down from a higher level. Top Up charges to 100% once, then the limit returns.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if battery.canControl {
                    Section("Battery helper") {
                        LabeledContent(
                            "Status",
                            value: battery.helperEnabled ? "Installed" : "Not installed")
                        if let message = battery.controlMessage {
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                        Button(
                            battery.helperEnabled
                                ? "Reinstall battery helper…" : "Install battery helper…"
                        ) {
                            battery.installHelper()
                        }
                        Text(
                            "Charge-limit writes need a root helper. One admin password. Same pattern as AlDente."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Section("Heat Protection") {
                    Toggle("Heat Protection", isOn: $battery.heatProtection)
                        .disabled(battery.isCalibrating)
                    if battery.heatProtection {
                        Stepper(
                            "Halt charging at \(battery.heatThresholdC)°C",
                            value: $battery.heatThresholdC, in: 30...45)
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
                        .disabled(!battery.canControl)
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

private struct APISettings: View {
    @Environment(AppState.self) private var app
    @AppStorage("apiEnabled") private var apiEnabled = false
    @AppStorage("apiPort") private var apiPort = 7799
    @State private var token = AppState.apiToken()

    var body: some View {
        Form {
            Toggle("Enable local REST API", isOn: $apiEnabled)
                .onChange(of: apiEnabled) { app.restartAPIServer() }
            TextField("Port", value: $apiPort, format: .number.grouping(.never))
                .onSubmit { app.restartAPIServer() }
            LabeledContent("Token") {
                HStack {
                    Text(token.prefix(12) + "…")
                        .font(.caption.monospaced())
                    Button("Copy", systemImage: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(token, forType: .string)
                    }
                    Button("Regenerate") {
                        UserDefaults.standard.removeObject(forKey: "apiToken")
                        token = AppState.apiToken()
                        app.restartAPIServer()
                    }
                }
            }
            Section("Endpoints") {
                Text("""
                    GET  /v1/meetings
                    GET  /v1/meetings/{id}
                    GET  /v1/meetings/{id}/transcript
                    GET  /v1/meetings/{id}/notes
                    POST /v1/meetings/{id}/enhance
                    """)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                Text("Authenticate with header:  Authorization: Bearer <token>")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct WebhookSettings: View {
    @Environment(AppState.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if app.webhooks.isEmpty {
                ContentUnavailableView(
                    "No webhooks",
                    systemImage: "arrow.up.right.square",
                    description: Text("Push transcripts and notes to your services when meetings end.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(app.webhooks) { webhook in
                            WebhookEditor(webhook: webhook)
                        }
                    }
                    .padding(8)
                }
            }
            Divider()
            HStack {
                Button("Add webhook", systemImage: "plus") {
                    app.saveWebhook(Webhook.new())
                }
                Spacer()
                Text("Payloads are signed: X-Granipa-Signature = sha256 HMAC of the body.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
        }
    }
}

private struct WebhookEditor: View {
    @Environment(AppState.self) private var app
    @State var webhook: Webhook

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("https://your-service.example/hook", text: $webhook.url)
                    .textFieldStyle(.roundedBorder)
                Toggle("", isOn: $webhook.enabled)
                    .labelsHidden()
                Button("Save") { app.saveWebhook(webhook) }
                Button(role: .destructive) {
                    app.deleteWebhook(id: webhook.id)
                } label: {
                    Image(systemName: "trash")
                }
            }
            HStack(spacing: 12) {
                ForEach(WebhookEvent.allCases, id: \.self) { event in
                    Toggle(
                        event.rawValue,
                        isOn: Binding(
                            get: { webhook.subscribes(to: event) },
                            set: { on in
                                var list = Set(webhook.eventList)
                                if on { list.insert(event) } else { list.remove(event) }
                                webhook.events = list.map(\.rawValue).sorted().joined(separator: ",")
                            }))
                    .font(.caption)
                }
            }
            LabeledContent("Secret") {
                Text(webhook.secret)
                    .font(.caption2.monospaced())
                    .textSelection(.enabled)
            }
            .font(.caption)
        }
        .padding(8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TemplateSettings: View {
    @Environment(AppState.self) private var app
    @State private var editing: MeetingTemplate?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: Binding(
                get: { editing?.id },
                set: { id in editing = app.templates.first { $0.id == id } }
            )) {
                ForEach(app.templates) { template in
                    HStack {
                        Text(template.name)
                        if template.isBuiltin {
                            Text("built-in")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tag(template.id)
                }
            }
            .frame(height: 120)
            Divider()
            if let template = editing {
                TemplateEditor(template: template) { updated in
                    app.saveTemplate(updated)
                    editing = updated
                } onDelete: {
                    app.deleteTemplate(id: template.id)
                    editing = nil
                }
                .id(template.id)
            } else {
                Text("Select a template to edit, or add a new one.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Button("Add template", systemImage: "plus") {
                    let template = MeetingTemplate(
                        id: UUID().uuidString,
                        name: "New template",
                        prompt: "Describe what to extract for this meeting type.",
                        isBuiltin: false)
                    app.saveTemplate(template)
                    editing = template
                }
                Spacer()
            }
            .padding(8)
        }
    }
}

private struct TemplateEditor: View {
    @State var template: MeetingTemplate
    let onSave: (MeetingTemplate) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: $template.name)
                Button("Save") { onSave(template) }
                Button("Delete", role: .destructive, action: onDelete)
                    .disabled(template.isBuiltin)
            }
            TextEditor(text: $template.prompt)
                .font(.callout)
        }
        .padding(8)
    }
}
