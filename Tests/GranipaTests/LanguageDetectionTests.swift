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

    @Test func probeAccumulatesWeightedConfidence() {
        var probe = LocaleProbe()
        probe.register(text: "1234567890", confidence: 0.8, isFinal: true)
        probe.register(text: "1234567890", confidence: 0.4, isFinal: false)
        #expect(abs(probe.averageConfidence - 0.6) < 0.0001)
        #expect(probe.finalsText == "1234567890")
    }
}
