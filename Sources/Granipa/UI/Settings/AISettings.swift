import SwiftUI

struct AISettings: View {
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

    var body: some View {
        let installedPath = LLMProviders.resolveExecutable(named: spec.executableName)?.path
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

struct TemplateSettings: View {
    @Environment(AppState.self) private var app
    @Binding var drafts: EditorDrafts<MeetingTemplate>
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
                TemplateEditor(template: draftBinding(template)) { updated in
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

    private func draftBinding(_ template: MeetingTemplate) -> Binding<MeetingTemplate> {
        Binding(
            get: { drafts[template] },
            set: { drafts[template] = $0 })
    }
}

private struct TemplateEditor: View {
    @Binding var template: MeetingTemplate
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
