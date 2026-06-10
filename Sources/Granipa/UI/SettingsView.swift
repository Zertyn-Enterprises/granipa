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
            APISettings()
                .tabItem { Label("API", systemImage: "network") }
            WebhookSettings()
                .tabItem { Label("Webhooks", systemImage: "arrow.up.right.square") }
        }
        .frame(width: 560, height: 460)
    }
}

private struct GeneralSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage("defaultLocale") private var defaultLocale = "en-US"
    @AppStorage("echoCancellation") private var echoCancellation = true
    @AppStorage("meetingDetectionEnabled") private var meetingDetection = true

    var body: some View {
        Form {
            Picker("Default meeting language", selection: $defaultLocale) {
                Text("English").tag("en-US")
                Text("Español").tag("es-ES")
            }
            Toggle("Detect meetings automatically", isOn: $meetingDetection)
                .onChange(of: meetingDetection) {
                    meetingDetection ? app.detector.start() : app.detector.stop()
                }
            Toggle("Echo cancellation (mic)", isOn: $echoCancellation)
            Text("Keep this on if you use speakers; it stops other participants' voices from bleeding into your mic channel.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
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
            .padding(8)
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
