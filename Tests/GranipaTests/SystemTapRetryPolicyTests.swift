import Testing

@testable import Granipa

@Suite struct SystemTapRetryPolicyTests {
    @Test func retriesOnlyWhileNoBufferHasEverArrived() {
        #expect(SystemTapRetryPolicy.shouldRetry(tapFailed: false, bufferCount: 0, attempts: 0))
        #expect(!SystemTapRetryPolicy.shouldRetry(tapFailed: false, bufferCount: 0, attempts: 1))
        #expect(!SystemTapRetryPolicy.shouldRetry(tapFailed: false, bufferCount: 1, attempts: 0))
        #expect(!SystemTapRetryPolicy.shouldRetry(tapFailed: false, bufferCount: 100, attempts: 0))
    }

    /// Regression: a tap whose restart threw after a device switch was
    /// treated as silence (buffers had arrived earlier) and never retried.
    @Test func retriesAFailedTapEvenAfterBuffersArrivedUpToTheBound() {
        #expect(SystemTapRetryPolicy.shouldRetry(tapFailed: true, bufferCount: 500, attempts: 2))
        #expect(!SystemTapRetryPolicy.shouldRetry(tapFailed: true, bufferCount: 500, attempts: 3))
    }
}

@Suite struct MicSilenceWindowTests {
    /// Per-tick increments of (buffers, non-silent buffers); verdict after the last tick.
    @Test func judgesSilenceOverTheLastThirtySeconds() {
        let quiet = (60, 0)
        let cases: [(String, [(Int, Int)], Bool)] = [
            ("window not full yet", Array(repeating: quiet, count: 6), false),
            ("silent for the whole window", Array(repeating: quiet, count: 7), true),
            // Regression: the old running total could never fire once sound had been heard.
            (
                "spoke earlier, silent for 30 s",
                [(60, 60), (60, 60)] + Array(repeating: quiet, count: 6), true
            ),
            ("sound inside the window", Array(repeating: quiet, count: 6) + [(60, 1)], false),
            ("buffers stopped arriving", [quiet] + Array(repeating: (0, 0), count: 6), false),
        ]
        for (name, ticks, expected) in cases {
            var window = MicSilenceWindow()
            var buffers = 0
            var nonSilent = 0
            var silent = false
            for (newBuffers, newNonSilent) in ticks {
                buffers += newBuffers
                nonSilent += newNonSilent
                silent = window.record(buffers: buffers, nonSilent: nonSilent)
            }
            #expect(silent == expected, "\(name)")
        }
    }
}
