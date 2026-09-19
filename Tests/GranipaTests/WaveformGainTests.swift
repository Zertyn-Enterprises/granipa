import Foundation
import Testing

@testable import Granipa

@Suite struct WaveformGainTests {
    @Test func silenceIsZero() {
        #expect(WaveformGain.display(0) == 0)
        #expect(WaveformGain.display(-0.02) == 0)
        #expect(WaveformGain.display(.nan) == 0)
        #expect(WaveformGain.display(.infinity) == 0)
    }

    @Test func deadQuietRoomIsAFloorNotZero() {
        // Room noise ~0.001 RMS: a visible idle floor, not a flat line.
        let floor = WaveformGain.display(0.001)
        #expect(floor > 0)
        #expect(floor < 0.25)
    }

    @Test func quietSpeechClearsMidHeight() {
        // The original bug: 0.01 RMS on a linear scale painted as a dot.
        let quiet = WaveformGain.display(0.01)
        #expect(quiet > 0.35)
        #expect(quiet < 0.5)
    }

    @Test func normalSpeechIsHighAndLoudClamps() {
        #expect(WaveformGain.display(0.04) > 0.6)
        #expect(WaveformGain.display(0.04) < 0.85)
        #expect(WaveformGain.display(0.08) == 1)
        #expect(WaveformGain.display(2.0) == 1)
    }

    @Test func mappingIsMonotonic() {
        let steps: [Float] = [0.001, 0.01, 0.02, 0.04, 0.08]
        let mapped = steps.map(WaveformGain.display)
        #expect(mapped == mapped.sorted())
        #expect(Set(mapped).count == mapped.count)
    }

    @Test func envelopeAttacksFasterThanItReleases() {
        let attack = WaveformEnvelope.next(current: 0.2, target: 1)
        let release = WaveformEnvelope.next(current: 1, target: 0.2)
        #expect(attack > 0.6)
        #expect(release > 0.7)
        #expect(attack <= 1)
        #expect(release >= 0.2)
    }

    @Test func envelopeRejectsInvalidInput() {
        #expect(WaveformEnvelope.next(current: .nan, target: .infinity) == 0)
    }
}
