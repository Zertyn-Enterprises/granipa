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
        }
        .frame(width: 520, height: 420)
    }
}

private struct GeneralSettings: View {
    @AppStorage("defaultLocale") private var defaultLocale = "en-US"
    @AppStorage("echoCancellation") private var echoCancellation = true

    var body: some View {
        Form {
            Picker("Default meeting language", selection: $defaultLocale) {
                Text("English").tag("en-US")
                Text("Español").tag("es-ES")
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
