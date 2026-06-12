import SwiftUI

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboardingCompleted") private var onboardingCompleted = false
    @State private var step = 0

    private let totalSteps = 3

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: permissions
                default: toolsAndShortcuts
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 28)
            .padding(.top, 36)
            .padding(.bottom, 20)

            footer
        }
        .frame(width: 540, height: 600)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onDisappear { onboardingCompleted = true }
    }

    // MARK: - Step 0

    private var welcome: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Welcome to Grañipa")
                .font(.system(size: 28, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
            VStack(spacing: 10) {
                bullet("waveform", "Records meetings without a bot — your mic and the other participants, straight from system audio.")
                bullet("cpu", "Transcribes live, on this Mac. Audio never leaves your machine.")
                bullet("wand.and.stars", "Turns your rough notes into polished reports using the AI subscription you already have — no API keys.")
                bullet("lock", "Everything stays local: no accounts, no cloud, no telemetry.")
            }
            .padding(.top, 6)
            Spacer()
        }
    }

    // MARK: - Step 1

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Permissions, explained")
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
            Text("macOS will ask for these as you use each feature — nothing is requested up front. This list shows the live status (revisit it anytime in Settings → Permissions):")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)

            PermissionsListView()
            Spacer()
        }
    }

    // MARK: - Step 2

    private var toolsAndShortcuts: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Your AI & shortcuts")
                .font(.system(size: 24, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.textPrimary)

            Text("AI providers detected (used for note enhancement — install and log into at least one):")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            VStack(spacing: 6) {
                ForEach(LLMProviders.all) { spec in
                    HStack {
                        Image(
                            systemName: LLMProviders.resolveExecutable(named: spec.executableName)
                                != nil ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(
                                LLMProviders.resolveExecutable(named: spec.executableName) != nil
                                    ? .green : Theme.textTertiary)
                        Text(spec.displayName)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                }
            }
            .padding(12)
            .card()

            if LLMProviders.all.allSatisfy({
                LLMProviders.resolveExecutable(named: $0.executableName) == nil
            }) {
                HStack(spacing: 6) {
                    Text("None yet? Paste in Terminal:")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                    Text("npm install -g @anthropic-ai/claude-code")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Theme.textPrimary)
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            "npm install -g @anthropic-ai/claude-code", forType: .string)
                        ToastController.shared.show("Copied")
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                }
                Text("Then run \"claude\" once — the browser opens to sign in with your subscription. That's the whole setup.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }

            Text("Shortcuts that work everywhere:")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            VStack(spacing: 6) {
                shortcutRow("⌥⇧V", "Clipboard history")
                shortcutRow("⌥⇧T", "Capture screen text (OCR)")
                shortcutRow("⌃⌥ ← → ↑ ↓ ⏎", "Snap & maximize windows")
            }
            .padding(12)
            .card()
            Spacer()
        }
    }

    // MARK: - Pieces

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 20)
    }

    private func shortcutRow(_ keys: String, _ what: String) -> some View {
        HStack {
            Text(keys)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
            Text(what)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<totalSteps, id: \.self) { index in
                    Circle()
                        .fill(index == step ? Theme.accent : Color.white.opacity(0.15))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            Button(step == totalSteps - 1 ? "Get started" : "Continue") {
                if step == totalSteps - 1 {
                    onboardingCompleted = true
                    dismiss()
                } else {
                    step += 1
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.accent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.border).frame(height: 1)
        }
    }
}
