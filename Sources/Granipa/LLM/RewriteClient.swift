import Foundation

enum RewriteProvider: String, Sendable {
    case off
    case spacexai
    case custom
}

enum RewriteError: LocalizedError {
    case http(Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .http(let code): return "Rewrite failed: HTTP \(code)"
        case .empty: return "Rewrite returned no text."
        }
    }
}

enum RewriteClient {
    static let spaceXAIBase = "https://api.x.ai/v1"
    static let spaceXAIModel = "grok-4.6"

    static let systemPrompt = """
        You clean up voice dictation. Return ONLY the rewritten text.
        Fix punctuation, capitalization, and obvious speech-to-text errors.
        Keep the original language and meaning. No quotes, no preamble, no explanation.
        """

    static func completionsURL(from rawBase: String) -> URL? {
        var base = rawBase.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        guard !base.isEmpty else { return nil }
        if base.hasSuffix("/chat/completions") { return URL(string: base) }
        return URL(string: base + "/chat/completions")
    }

    static func parseContent(from json: String) -> String? {
        guard let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = object["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { return nil }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func rewrite(_ text: String) async throws -> String {
        let provider = RewriteProvider(
            rawValue: UserDefaults.standard.string(forKey: "dictationRewrite") ?? "off")
            ?? .off
        switch provider {
        case .off:
            return text
        case .spacexai:
            guard let key = KeychainStore.get(account: KeychainStore.spaceXAIKeyAccount) else {
                return text
            }
            guard let url = completionsURL(from: spaceXAIBase) else {
                throw RewriteError.empty
            }
            return try await post(
                url: url,
                model: spaceXAIModel,
                apiKey: key,
                text: text,
                extra: ["search_parameters": ["mode": "off"]])
        case .custom:
            let raw = UserDefaults.standard.string(forKey: "rewriteCustomURL") ?? ""
            guard let url = completionsURL(from: raw) else {
                throw RewriteError.empty
            }
            let model = UserDefaults.standard.string(forKey: "rewriteCustomModel") ?? ""
            guard !model.isEmpty else { throw RewriteError.empty }
            let key = KeychainStore.get(account: KeychainStore.rewriteCustomKeyAccount)
            return try await post(url: url, model: model, apiKey: key, text: text, extra: [:])
        }
    }

    private static func post(
        url: URL,
        model: String,
        apiKey: String?,
        text: String,
        extra: [String: Any]
    ) async throws -> String {
        var body: [String: Any] = [
            "model": model,
            "temperature": 0.2,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text],
            ],
        ]
        for (key, value) in extra { body[key] = value }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            throw RewriteError.http(http.statusCode)
        }
        let json = String(data: data, encoding: .utf8) ?? ""
        guard let content = parseContent(from: json) else { throw RewriteError.empty }
        return content
    }
}
