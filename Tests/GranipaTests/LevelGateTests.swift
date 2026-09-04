import Testing

@testable import Granipa

@Suite struct LevelGateTests {
    @Test func throttlesUpdatesInsideTheInterval() {
        let gate = LevelGate(minInterval: 60)

        #expect(gate.shouldPublish(.mic))
        #expect(!gate.shouldPublish(.mic))
    }
}
