import Testing

@testable import Granipa

/// The clock is created once per meeting and outlives session rotations, so
/// Muse timestamps stay meeting-relative across the 55-minute swap.
@Suite struct MeetingClockTests {
    @Test func timesContinueMonotonicallyAcrossRotation() {
        let clock = MeetingClock()
        clock.advance(to: 600)
        clock.markTurn(at: 600)
        // Rotation: same clock, fresh session — nothing resets it.
        clock.advance(to: 3_900)
        clock.markTurn(at: 3_900)
        #expect(clock.seconds() == 3_900)
        #expect(clock.turnStart() == 3_900)
    }

    @Test func speakerLabelFollowsLatestSession() {
        let clock = MeetingClock()
        clock.setSpeaker("A")
        #expect(clock.speakerName() == "Speaker A")
        // A new session starts unlabeled until Muse sends its first speaker.
        clock.setSpeaker("")
        #expect(clock.speakerName() == "Them")
    }

    @Test func rotationHappensBeforeTheSixtyMinuteCap() {
        #expect(MuseSystemTranscriber.sessionRotateInterval == 55 * 60)
    }
}
