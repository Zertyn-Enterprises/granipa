import Carbon.HIToolbox
import SwiftUI

struct DictationSettings: View {
    @Environment(AppState.self) private var app
    @AppStorage("dictationEngine") private var engine = "local"
    @AppStorage("meetingSystemEngine") private var meetingSystemEngine = "local"
    @AppStorage("dictationAutoPaste") private var autoPaste = true
    @AppStorage("dictationKeywords") private var keywords = ""
    @AppStorage("dictationShortcut") private var shortcut = "rightOption"
    @AppStorage("dictationLocale") private var dictationLocale = "auto"
    @AppStorage("probeLocales") private var probeLocalesRaw = "en-US,es-ES"
    @AppStorage("dictationRewrite") private var rewrite = "off"
    @AppStorage("rewriteCustomURL") private var rewriteURL = RewriteClient.defaultCustomURL
    @AppStorage("rewriteCustomModel") private var rewriteModel = RewriteClient.defaultCustomModel
    @Binding var drafts: DictationKeyDrafts

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
                Text("Hold to talk, release to paste. A quick tap toggles; press again to stop. Esc cancels the dictation in progress, held or toggled. Right Option and Right Command need Accessibility (same grant as auto-paste) so they work in other apps. Option+Space uses a Carbon hotkey and does not.")
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
                        Text(LanguageDetection.displayName(id)).tag(id)
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
            if engine == "muse" || meetingSystemEngine == "muse" {
                Section("Muse") {
                    SecureField("Meta API key", text: $drafts.museKey)
                    Button("Save key") {
                        drafts.keySaved = KeychainStore.set(
                            drafts.museKey, account: KeychainStore.museAPIKeyAccount)
                    }
                    if drafts.keySaved == false {
                        Text("Could not save the key in Keychain.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if drafts.keySaved == true {
                        Text("Saved in Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text("Audio is sent with zero-data-retention requested. $0.18/hour.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Vocabulary hints (comma-separated)", text: $keywords)
                    Text("Names, products, jargon Muse should prefer. Used by dictation and meetings.")
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
                    SecureField("SpaceXAI API key", text: $drafts.spaceXAIKey)
                    Button("Save SpaceXAI key") {
                        drafts.spaceXAIKeySaved = KeychainStore.set(
                            drafts.spaceXAIKey, account: KeychainStore.spaceXAIKeyAccount)
                    }
                    if drafts.spaceXAIKeySaved == false {
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
                    SecureField("API key (optional)", text: $drafts.customKey)
                    Button("Save endpoint key") {
                        drafts.customKeySaved = KeychainStore.set(
                            drafts.customKey, account: KeychainStore.rewriteCustomKeyAccount)
                    }
                    if drafts.customKeySaved == false {
                        Text("Could not save the key in Keychain.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    } else if drafts.customKeySaved == true {
                        Text("Saved in Keychain.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            drafts.loadOnce { KeychainStore.get(account: $0) }
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
