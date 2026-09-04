import Foundation
import Testing

@testable import Granipa

@Suite struct LanguageDetectionTests {
    @Test func spanishSpeechWinsWhenEnglishModelEmitsSpanishJunk() {
        // Real case: the en-US model transcribing Spanish speech produced this.
        let winner = LanguageDetection.decide(
            enText: "Sun cumulo de, de masnos una solaiolo, medite",
            enConfidence: 0.42,
            esText: "son cúmulo de granos, una soleada, medité",
            esConfidence: 0.81,
            force: false)
        #expect(winner == "es-ES")
    }

    @Test func englishSpeechWinsByConfidenceGap() {
        let winner = LanguageDetection.decide(
            enText: "we should review the quarterly roadmap before the launch next week",
            enConfidence: 0.88,
            esText: "huy sur revió de cuarterli redmap before de lonch nes huic",
            esConfidence: 0.46,
            force: false)
        #expect(winner == "en-US")
    }

    @Test func waitsForEnoughText() {
        let winner = LanguageDetection.decide(
            enText: "hello there",
            enConfidence: 0.9,
            esText: "jelou der",
            esConfidence: 0.4,
            force: false)
        #expect(winner == nil)
    }

    @Test func forceAlwaysPicksWithAnyText() {
        let winner = LanguageDetection.decide(
            enText: "hello there",
            enConfidence: 0.9,
            esText: "jelou der",
            esConfidence: 0.4,
            force: true)
        #expect(winner == "en-US")
    }

    @Test func forceWithNoTextReturnsNil() {
        let winner = LanguageDetection.decide(
            enText: "", enConfidence: 0,
            esText: "", esConfidence: 0,
            force: true)
        #expect(winner == nil)
    }

    @Test func threeWayCrossVotePicksFrench() {
        let winner = LanguageDetection.decide(
            [
                LanguageProbeResult(
                    localeID: "en-US",
                    text: "je voudrais discuter du budget avec vous aujourd'hui",
                    confidence: 0.4),
                LanguageProbeResult(
                    localeID: "es-ES",
                    text: "quiero hablar del presupuesto del año que viene",
                    confidence: 0.5),
                LanguageProbeResult(
                    localeID: "fr-FR",
                    text: "je voudrais discuter du budget de l'année prochaine avec vous",
                    confidence: 0.8),
            ],
            force: false)
        #expect(winner == "fr-FR")
    }

    @Test func confidenceGapDecidesAmongThree() {
        let winner = LanguageDetection.decide(
            [
                LanguageProbeResult(
                    localeID: "en-US",
                    text: "we should review the quarterly roadmap before the launch next week",
                    confidence: 0.9),
                LanguageProbeResult(
                    localeID: "es-ES",
                    text: "hablemos del presupuesto y del calendario del próximo trimestre",
                    confidence: 0.4),
                LanguageProbeResult(
                    localeID: "fr-FR",
                    text: "je pense que nous devrions revoir le calendrier ensemble",
                    confidence: 0.3),
            ],
            force: false)
        #expect(winner == "en-US")
    }

    @Test func startLocalesUsesOneAnalyzer() {
        let probes = ["en-US", "es-ES"]
        #expect(
            LanguageDetection.startLocales(requested: "fr-FR", last: "en-US", probes: probes)
                == ["fr-FR"])
        #expect(
            LanguageDetection.startLocales(requested: "auto", last: "es-ES", probes: probes)
                == ["es-ES"])
        #expect(
            LanguageDetection.startLocales(requested: "auto", last: nil, probes: probes)
                == ["en-US"])
        #expect(
            LanguageDetection.startLocales(requested: "auto", last: "ja-JP", probes: probes)
                == ["en-US"])
    }

    @Test func parseProbeLocalesDedupesAndCaps() {
        #expect(LanguageDetection.parseProbeLocales(nil) == ["en-US", "es-ES"])
        #expect(LanguageDetection.parseProbeLocales("") == ["en-US", "es-ES"])
        #expect(
            LanguageDetection.parseProbeLocales(" fr-FR ,de-DE, fr-FR, ja-JP, ko-KR")
                == ["fr-FR", "de-DE", "ja-JP"])
    }

    @Test func probeAccumulatesWeightedConfidence() {
        var probe = LocaleProbe()
        probe.register(text: "1234567890", confidence: 0.8, isFinal: true)
        probe.register(text: "1234567890", confidence: 0.4, isFinal: false)
        #expect(abs(probe.averageConfidence - 0.6) < 0.0001)
        #expect(probe.finalsText == "1234567890")
    }

    @Test func systemHintVoteBreaksForceTie() {
        // Probe texts too short to read (<10 chars): no cross-vote, equal
        // confidence. Without a hint the first non-empty candidate wins.
        let probes = [
            LanguageProbeResult(localeID: "en-US", text: "hey", confidence: 0.5),
            LanguageProbeResult(localeID: "es-ES", text: "hol", confidence: 0.5),
        ]
        #expect(LanguageDetection.decide(probes, force: true) == "en-US")
        #expect(
            LanguageDetection.decide(
                probes, force: true, systemHint: "hola qué tal estás hoy"
            ) == "es-ES")
    }

    @Test func systemHintNeverDecidesWithoutMicText() {
        // adopt() is irreversible: the hint only strengthens candidates that
        // already hold mic text, so a Spanish hint can't elect a probe that
        // captured nothing — even a long one, even at force.
        let probes = [
            LanguageProbeResult(localeID: "en-US", text: "hey", confidence: 0.5),
            LanguageProbeResult(localeID: "es-ES", text: "", confidence: 0),
        ]
        let hint = "buenas, vamos a empezar con la revisión del proyecto de hoy"
        #expect(
            LanguageDetection.decide(probes, force: true, systemHint: hint) == "en-US")
    }

    @Test func systemHintInUnprobedLanguageIsInert() {
        // System audio in a language nobody probes must not vote for anyone:
        // the decision falls through to the same outcome as no hint.
        let probes = [
            LanguageProbeResult(localeID: "en-US", text: "hello there how are you", confidence: 0.9),
            LanguageProbeResult(localeID: "es-ES", text: "hol", confidence: 0.4),
        ]
        let frenchHint = "bonjour, allons-nous commencer la réunion"
        #expect(
            LanguageDetection.decide(probes, force: false, systemHint: frenchHint)
                == LanguageDetection.decide(probes, force: false))
    }
}
