import Testing

@testable import Granipa

@Suite struct LevelGateTests {
    @Test func throttlesLargeChangesInsideTheInterval() {
        let gate = LevelGate(minInterval: 60)

        #expect(gate.shouldPublish(.mic, 0))
        #expect(!gate.shouldPublish(.mic, 1))
    }
}
