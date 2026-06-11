import Foundation
import NaturalLanguage

struct LocaleProbe {
    var finalsText = ""
    var confidenceSum = 0.0
    var confidenceWeight = 0.0

    var averageConfidence: Double {
        confidenceWeight > 0 ? confidenceSum / confidenceWeight : 0
    }

    mutating func register(text: String, confidence: Double?, isFinal: Bool) {
        if isFinal {
            finalsText += (finalsText.isEmpty ? "" : " ") + text
        }
        if let confidence {
            let weight = Double(text.count)
            confidenceSum += confidence * weight
            confidenceWeight += weight
        }
    }
}

enum LanguageDetection {
    static let autoLocales = ["en-US", "es-ES"]

    static func dominantLanguage(of text: String) -> NLLanguage? {
        guard text.count >= 10 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    static func decide(
        enText: String, enConfidence: Double,
        esText: String, esConfidence: Double,
        force: Bool
    ) -> String? {
        if !force && max(enText.count, esText.count) < 40 { return nil }
        if enText.isEmpty && esText.isEmpty { return nil }

        // A model transcribing the wrong language emits text that doesn't read as
        // its own language (the en-US model produces Spanish-looking junk for
        // Spanish speech). That self-mismatch is the strongest signal.
        let enReads = dominantLanguage(of: enText)
        let esReads = dominantLanguage(of: esText)
        if enReads == .spanish && esReads != .english { return "es-ES" }
        if esReads == .english && enReads != .spanish { return "en-US" }

        let gap = enConfidence - esConfidence
        if abs(gap) > 0.1 { return gap > 0 ? "en-US" : "es-ES" }

        guard force else { return nil }
        if enText.isEmpty { return "es-ES" }
        if esText.isEmpty { return "en-US" }
        return enConfidence >= esConfidence ? "en-US" : "es-ES"
    }
}
