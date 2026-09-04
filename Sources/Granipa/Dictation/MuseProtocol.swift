import Foundation

enum MuseEvent: Equatable, Sendable {
    case handshake(sessionID: String)
    case transcript(text: String, isFinal: Bool)
    case speechStart
    case speaker(label: String)
    case speechComplete(text: String)
    case error(String)
    case ignored
}

enum MuseEventParser {
    static func parse(_ json: String) -> MuseEvent {
        guard let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return .ignored
        }
        return parse(object)
    }

    static func parse(_ object: [String: Any]) -> MuseEvent {
        if let type = object["type"] as? String {
            switch type {
            case "transcript":
                let text = object["transcript"] as? String ?? ""
                let isFinal = object["final"] as? Bool ?? false
                return .transcript(text: text, isFinal: isFinal)
            case "speechStart":
                return .speechStart
            case "speaker":
                return .speaker(label: object["label"] as? String ?? "")
            case "speechComplete":
                return .speechComplete(text: object["transcript"] as? String ?? "")
            case "error":
                return .error(object["message"] as? String ?? "Muse transcription failed.")
            default:
                return .ignored
            }
        }
        if let sessionID = object["sessionId"] as? String, !sessionID.isEmpty {
            return .handshake(sessionID: sessionID)
        }
        return .ignored
    }
}

enum MuseLanguages {
    /// Maps BCP-47 language codes onto Muse `languageBias` names.
    static let namesByCode: [String: String] = [
        "ar": "Arabic",
        "bn": "Bengali",
        "nl": "Dutch",
        "en": "English",
        "fr": "French",
        "de": "German",
        "he": "Hebrew",
        "hi": "Hindi",
        "id": "Indonesian",
        "it": "Italian",
        "ja": "Japanese",
        "kn": "Kannada",
        "ko": "Korean",
        "ms": "Malay",
        "zh": "Mandarin Chinese",
        "yue": "Mandarin Chinese",
        "mr": "Marathi",
        "pl": "Polish",
        "pt": "Portuguese",
        "es": "Spanish",
        "tl": "Tagalog",
        "ta": "Tamil",
        "te": "Telugu",
        "th": "Thai",
        "tr": "Turkish",
        "vi": "Vietnamese",
    ]

    static func bias(forLocaleIDs ids: [String]) -> [String] {
        var seen = Set<String>()
        var names: [String] = []
        for id in ids {
            let code = String(id.prefix(2)).lowercased()
            guard let name = namesByCode[code], seen.insert(name).inserted else { continue }
            names.append(name)
        }
        return names
    }

    static func keywords(from raw: String) -> [String] {
        var seen = Set<String>()
        return raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }
}
