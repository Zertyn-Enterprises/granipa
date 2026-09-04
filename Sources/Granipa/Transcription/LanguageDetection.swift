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

    /// One SpeechAnalyzer per channel. Parallel locale probes (2–3 × mic+system)
    /// peg the CPU and freeze the UI during Record.
    static func startLocales(requested: String, last: String?, probes: [String]? = nil)
        -> [String]
    {
        if requested != "auto" { return [requested] }
        let list =
            probes
            ?? parseProbeLocales(UserDefaults.standard.string(forKey: "probeLocales"))
        if let last, list.contains(last) { return [last] }
        return [list[0]]
    }

    static func dominantLanguage(of text: String) -> NLLanguage? {
        guard text.count >= 10 else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage
    }

    static func decide(
        _ probes: [LanguageProbeResult], force: Bool, systemHint: String? = nil
    ) -> String? {
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
        // System audio transcribed by a locale-independent model (Muse) votes
        // for the candidate its text reads as — same evidence, other channel.
        // The vote only strengthens candidates that already hold mic text:
        // adopt() is irreversible, so the hint breaks ties, it never decides
        // alone.
        if let read = systemHint.flatMap({ dominantLanguage(of: $0)?.rawValue }).map({
            String($0.prefix(2))
        }) {
            for probe in nonEmpty where code(probe.localeID) == read {
                crossVoted.insert(probe.localeID)
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
