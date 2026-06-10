import Foundation

enum LLMService {
    static func generate(
        providerID: String,
        prompt: String,
        timeout: TimeInterval = 600
    ) async throws -> String {
        guard let spec = LLMProviders.spec(id: providerID) else {
            throw LLMError.unknownProvider(providerID)
        }
        guard let executable = LLMProviders.resolveExecutable(named: spec.executableName) else {
            throw LLMError.executableNotFound(spec.executableName)
        }

        var outputFile: URL?
        var arguments: [String] = []
        for argument in spec.arguments {
            switch argument {
            case LLMProviderSpec.promptPlaceholder:
                arguments.append(prompt)
            case LLMProviderSpec.outputPlaceholder:
                let file = FileManager.default.temporaryDirectory
                    .appendingPathComponent("granipa-llm-\(UUID().uuidString).txt")
                outputFile = file
                arguments.append(file.path)
            default:
                arguments.append(argument)
            }
        }

        let output = try await LLMRunner.run(
            executable: executable,
            arguments: arguments,
            stdin: spec.promptViaStdin ? prompt : nil,
            timeout: timeout)

        let text: String
        if let outputFile {
            defer { try? FileManager.default.removeItem(at: outputFile) }
            text = (try? String(contentsOf: outputFile, encoding: .utf8)) ?? output.stdout
        } else {
            text = output.stdout
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LLMError.emptyOutput }
        return trimmed
    }
}
