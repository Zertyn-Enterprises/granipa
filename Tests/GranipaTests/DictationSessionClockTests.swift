import Foundation
import Testing

@testable import Granipa

@Suite @MainActor struct DictationSessionClockTests {
    #if DEBUG
        @Test func sessionStartsOnEnteringPreparingAndSurvivesTheWholeRun() async {
            var captureAllowed = false
            let controller = DictationController(
                testHooks: DictationTestHooks(beforeCapture: {
                    while !captureAllowed, !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(2))
                    }
                }))
            let clock = DictationSessionClock(controller: controller)
            clock.beginObserving()
            #expect(clock.sessionStartedAt == nil)
            defer { controller.cancel() }

            controller.toggleFromMenu()
            #expect(await eventually { clock.sessionStartedAt != nil })
            // Still preparing: the start is stamped on entering it, not on leaving it.
            #expect(controller.phase == .preparing)
            let started = clock.sessionStartedAt

            captureAllowed = true
            #expect(await eventually { controller.phase == .listening })
            controller.cancel()
            #expect(await eventually { controller.phase == .idle })
            #expect(clock.sessionStartedAt == started)
        }

        private func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
            for _ in 0..<160 where !condition() {
                try? await Task.sleep(for: .milliseconds(5))
            }
            return condition()
        }
    #endif

    @Test func listeningAloneDoesNotInventAStart() {
        // Armed mid-session (start missed): the clock stays unknown, never guesses.
        let clock = DictationSessionClock()
        clock.track(.listening)
        #expect(clock.sessionStartedAt == nil)
    }

    @Test func retryOrNewPressStartsAFreshSession() {
        // Two presses can share a wall-clock instant, so the reset is driven by
        // known-distinct dates instead of `.now`.
        let clock = DictationSessionClock()
        let firstPress = Date(timeIntervalSinceReferenceDate: 100)
        let retryPress = Date(timeIntervalSinceReferenceDate: 200)
        clock.track(.preparing, now: firstPress)
        let first = clock.sessionStartedAt
        clock.track(.failed("boom"))
        clock.track(.preparing, now: retryPress)
        #expect(clock.sessionStartedAt != first)
        #expect(clock.sessionStartedAt == retryPress)
    }

    @Test func elapsedLabelFormatsClockDigitsAndClamps() {
        let start = Date(timeIntervalSinceReferenceDate: 0)
        #expect(DictationSessionClock.elapsedLabel(startedAt: nil) == nil)
        #expect(DictationSessionClock.elapsedLabel(startedAt: start, now: start) == "00:00:00")
        #expect(
            DictationSessionClock.elapsedLabel(startedAt: start, now: start.addingTimeInterval(75))
                == "00:01:15")
        #expect(
            DictationSessionClock.elapsedLabel(
                startedAt: start, now: start.addingTimeInterval(3_723)) == "01:02:03")
        #expect(
            DictationSessionClock.elapsedLabel(
                startedAt: start.addingTimeInterval(10), now: start) == "00:00:00")
    }
}
