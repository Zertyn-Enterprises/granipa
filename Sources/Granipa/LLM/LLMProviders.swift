import Foundation

struct LLMProviderSpec: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let executableName: String
    let arguments: [String]
    let promptViaStdin: Bool
    let installCommand: String?
    let loginHint: String

    static let promptPlaceholder = "{PROMPT}"
    static let outputPlaceholder = "{OUTPUT}"
}

enum LLMProviders {
    static let all: [LLMProviderSpec] = [
        LLMProviderSpec(
            id: "claude",
            displayName: "Claude (Claude Code)",
            executableName: "claude",
            arguments: ["-p", "--output-format", "text"],
            promptViaStdin: true,
            installCommand: "npm install -g @anthropic-ai/claude-code",
            loginHint: "Run \"claude\" once in Terminal — it opens the browser to sign in with your Claude subscription."),
        LLMProviderSpec(
            id: "codex",
            displayName: "Codex (ChatGPT)",
            executableName: "codex",
            arguments: [
                "exec", "--skip-git-repo-check", "-s", "read-only",
                "-o", LLMProviderSpec.outputPlaceholder, "-",
            ],
            promptViaStdin: true,
            installCommand: "npm install -g @openai/codex",
            loginHint: "Run \"codex\" once in Terminal — it signs in with your ChatGPT account in the browser."),
        LLMProviderSpec(
            id: "gemini",
            displayName: "Gemini",
            executableName: "gemini",
            arguments: ["-p", LLMProviderSpec.promptPlaceholder],
            promptViaStdin: false,
            installCommand: "npm install -g @google/gemini-cli",
            loginHint: "Run \"gemini\" once in Terminal — it signs in with your Google account in the browser."),
        LLMProviderSpec(
            id: "grok",
            displayName: "Grok",
            executableName: "grok",
            arguments: ["-p", LLMProviderSpec.promptPlaceholder],
            promptViaStdin: false,
            installCommand: nil,
            loginHint: "Install the Grok CLI from xAI's documentation, then run \"grok\" once to sign in."),
    ]

    static func spec(id: String) -> LLMProviderSpec? {
        all.first { $0.id == id }
    }

    static func resolveExecutable(named name: String) -> URL? {
        let home = NSHomeDirectory()
        var candidates = [
            "\(home)/.local/bin/\(name)",
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "\(home)/.bun/bin/\(name)",
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            candidates += path.split(separator: ":").map { "\($0)/\(name)" }
        }
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }
        return nil
    }
}
