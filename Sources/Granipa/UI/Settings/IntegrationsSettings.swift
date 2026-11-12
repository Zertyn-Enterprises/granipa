import SwiftUI

struct APISettings: View {
    @Environment(AppState.self) private var app
    @AppStorage("apiEnabled") private var apiEnabled = false
    @AppStorage("apiPort") private var apiPort = 7799
    @State private var token = AppState.apiToken()

    var body: some View {
        Form {
            Toggle("Enable local REST API", isOn: $apiEnabled)
                .onChange(of: apiEnabled) { app.restartAPIServer() }
            TextField(
                "Port",
                value: Binding(
                    get: { apiPort },
                    set: { apiPort = Int(APIServer.port(stored: $0)) }),
                format: .number.grouping(.never))
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

struct WebhookSettings: View {
    @Environment(AppState.self) private var app
    @Binding var drafts: EditorDrafts<Webhook>

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
                            WebhookEditor(webhook: draftBinding(webhook))
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

    private func draftBinding(_ webhook: Webhook) -> Binding<Webhook> {
        Binding(
            get: { drafts[webhook] },
            set: { drafts[webhook] = $0 })
    }
}

private struct WebhookEditor: View {
    @Environment(AppState.self) private var app
    @Binding var webhook: Webhook

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
