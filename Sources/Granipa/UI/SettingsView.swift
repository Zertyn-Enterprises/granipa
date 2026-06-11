import ServiceManagement
import Speech
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            AISettings()
                .tabItem { Label("AI", systemImage: "wand.and.stars") }
            TemplateSettings()
                .tabItem { Label("Templates", systemImage: "doc.text") }
            ProductivitySettings()
                .tabItem { Label("Productivity", systemImage: "doc.on.clipboard") }
            WindowSettings()
                .tabItem { Label("Windows", systemImage: "macwindow.on.rectangle") }
            APISettings()
                .tabItem { Label("API", systemImage: "network") }
            WebhookSettings()
                .tabItem { Label("Webhooks", systemImage: "arrow.up.right.square") }
        }
        .frame(width: 560, height: 460)
        .preferredColorScheme(.dark)
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage("defaultLocale") private var defaultLocale = "auto"
    @AppStorage("echoCancellation") private var echoCancellation = true
    @AppStorage("meetingDetectionEnabled") private var meetingDetection = true
    @AppStorage("autoStopMode") private var autoStopMode = "ask"
    @AppStorage("audioRetentionDays") private var audioRetentionDays = 0
    @AppStorage("probeLocales") private var probeLocalesRaw = "en-US,es-ES"
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var supportedLocales: [Locale] = []

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
                    Text("Each recording probes your selected languages in parallel for the first seconds and keeps the one that matches what it hears. Each language downloads its on-device model once.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Toggle("Detect meetings automatically", isOn: $meetingDetection)
                .onChange(of: meetingDetection) {
                    meetingDetection ? app.detector.start() : app.detector.stop()
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
            Text("Keep this on if you use speakers; it stops other participants' voices from bleeding into your mic channel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .task {
            let locales = await SpeechTranscriber.supportedLocales
            supportedLocales = locales.sorted {
                languageName($0.identifier(.bcp47)) < languageName($1.identifier(.bcp47))
            }
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
        Locale.current.localizedString(forIdentifier: id)?.capitalized ?? id
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
                Text("Splits remote participants into Speaker 1, 2, 3… after the meeting (local CoreML model, ~130 MB downloaded on first use).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Infer speaker names with AI", isOn: $inferSpeakerNames)
                    .disabled(!diarizationEnabled)
            }

            Section("Detected CLIs") {
                ForEach(LLMProviders.all) { spec in
                    LabeledContent(spec.displayName) {
                        if let url = LLMProviders.resolveExecutable(named: spec.executableName) {
                            Text(url.path)
                                .font(.caption)
                                .foregroundStyle(.green)
                        } else {
                            Text("Not found")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
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
                LabeledContent("Open panel", value: "⌥⇧V")
                Toggle("Paste automatically after selecting", isOn: $autoPaste)
                    .onChange(of: autoPaste) {
                        if autoPaste, !PasteService.isTrusted {
                            PasteService.requestTrust()
                        }
                    }
                Text("Auto-paste sends ⌘V to the active app and needs Accessibility permission (System Settings → Privacy & Security → Accessibility).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Keeps the last 500 items locally. Entries marked confidential by password managers are never captured.")
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
                LabeledContent("Capture screen text", value: "⌥⇧T")
                Text("Select a screen region; recognized text (Spanish/English) is copied to the clipboard. Needs Screen Recording permission on first use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct WindowSettings: View {
    @AppStorage("windowSnappingEnabled") private var snapping = true

    var body: some View {
        Form {
            Toggle("Window snapping shortcuts", isOn: $snapping)
            Text("Uses the same Accessibility permission as auto-paste. All shortcuts are Control + Option.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Section("Halves & maximize") {
                LabeledContent("Left / Right half", value: "⌃⌥←  ⌃⌥→")
                LabeledContent("Top / Bottom half", value: "⌃⌥↑  ⌃⌥↓")
                LabeledContent("Maximize", value: "⌃⌥⏎")
                LabeledContent("Center", value: "⌃⌥C")
                LabeledContent("Restore previous size", value: "⌃⌥⌫")
            }
            Section("Quarters") {
                LabeledContent("Top left / Top right", value: "⌃⌥U  ⌃⌥I")
                LabeledContent("Bottom left / Bottom right", value: "⌃⌥J  ⌃⌥K")
            }
            Section("Thirds") {
                LabeledContent("First / Center / Last third", value: "⌃⌥D  ⌃⌥F  ⌃⌥G")
            }
        }
        .formStyle(.grouped)
    }
}

private struct APISettings: View {
    @Environment(AppState.self) private var app
    @AppStorage("apiEnabled") private var apiEnabled = true
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
