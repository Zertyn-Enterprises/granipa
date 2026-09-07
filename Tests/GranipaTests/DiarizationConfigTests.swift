import FluidAudio
import Testing

@testable import Granipa

@Suite struct DiarizationConfigTests {
    @Test func diarizerReusesEmbeddingsForStableSpeakerMasks() {
        guard case .maskSimilarity(let threshold) =
            DiarizationService.diarizerConfig.embedding.skipStrategy
        else {
            Issue.record("expected the maskSimilarity skip strategy")
            return
        }
        #expect(threshold == 0.95)
    }
}
