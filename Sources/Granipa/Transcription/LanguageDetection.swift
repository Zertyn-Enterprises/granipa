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

struct LanguageProbeResult: Sendable {
    let localeID: String
    let text: String
    let confidence: Double
}

enum LanguageDetection {
    static let defaultProbeLocales = ["en-US", "es-ES"]
    static let maxProbeLocales = 3

    static func parseProbeLocales(_ raw: String?) -> [String] {
        var seen = Set<String>()
        let parsed = (raw ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
        return parsed.isEmpty ? defaultProbeLocales : Array(parsed.prefix(maxProbeLocales))
    }

    static func dominantLanguage(of text: String) -> NLLanguage? {
        guard text.count >= 10 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    static func decide(_ probes: [LanguageProbeResult], force: Bool) -> String? {
        let nonEmpty = probes.filter { !$0.text.isEmpty }
        guard !nonEmpty.isEmpty else { return nil }
        if !force, (probes.map { $0.text.count }.max() ?? 0) < 40 { return nil }

        func code(_ localeID: String) -> String { String(localeID.prefix(2)) }

        // What each model's own output reads as (2-letter code).
        var reads: [String: String] = [:]
        for probe in probes {
            if let detected = dominantLanguage(of: probe.text)?.rawValue {
                reads[probe.localeID] = String(detected.prefix(2))
            }
        }

        // A model transcribing the wrong language emits text that reads as the
        // RIGHT language — a cross-vote for the candidate it reads as. That
        // self-mismatch is the strongest signal.
        var crossVoted = Set<String>()
        for probe in probes {
            guard let read = reads[probe.localeID], read != code(probe.localeID) else { continue }
            for other in probes
            where other.localeID != probe.localeID && code(other.localeID) == read {
                crossVoted.insert(other.localeID)
            }
        }
        // A cross-voted candidate only wins cleanly if its own output doesn't
        // read as some other candidate's language.
        let cleanWinners = crossVoted.filter { id in
            guard let own = reads[id], own != code(id) else { return true }
            return !probes.contains { $0.localeID != id && code($0.localeID) == own }
        }
        if cleanWinners.count == 1, let winner = cleanWinners.first {
            return winner
        }

        let ranked = probes.sorted { $0.confidence > $1.confidence }
        if ranked.count >= 2, ranked[0].confidence - ranked[1].confidence > 0.1 {
            return ranked[0].localeID
        }

        guard force else { return nil }
        var best = nonEmpty[0]
        for candidate in nonEmpty.dropFirst() where candidate.confidence > best.confidence {
            best = candidate
        }
        return best.localeID
    }

    static func decide(
        enText: String, enConfidence: Double,
        esText: String, esConfidence: Double,
        force: Bool
    ) -> String? {
        decide(
            [
                LanguageProbeResult(localeID: "en-US", text: enText, confidence: enConfidence),
                LanguageProbeResult(localeID: "es-ES", text: esText, confidence: esConfidence),
            ],
            force: force)
    }
}
