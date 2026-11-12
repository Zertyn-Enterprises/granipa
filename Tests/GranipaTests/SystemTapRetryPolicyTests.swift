import Foundation
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

@Suite struct CaptureHealthWatchTests {
    private func sample(
        _ buffers: Int, _ frames: Int64, failed: Bool = false
    ) -> ChannelSample {
        ChannelSample(
            buffers: buffers, nonSilent: buffers, framesWritten: frames, startFailed: failed)
    }

    /// Each case feeds ticks and checks the verdict of the last one.
    @Test func micVerdicts() {
        let cap = MicHealthWatch.maxRestarts
        let failedRestarts = Array(repeating: sample(500, 1000, failed: true), count: cap)
        let cases: [(String, [ChannelSample], MicHealthWatch.Verdict)] = [
            // Regression: buffers kept arriving while nothing reached the file.
            ("not saved", [sample(100, 0), sample(200, 0)], .init(warning: .show(.notSaved))),
            (
                "last restart failed", [sample(500, 1000), sample(500, 1000, failed: true)],
                .init(restartRecreatingFile: false, warning: .show(.restartFailed))
            ),
            (
                "cap reached",
                [sample(500, 1000)] + failedRestarts + [sample(500, 1000, failed: true)],
                .init(warning: .show(.unrecoverable))
            ),
            (
                "cap resets once audio is saved again",
                [sample(500, 1000)] + failedRestarts
                    + [sample(600, 2000), sample(600, 2000, failed: true)],
                .init(restartRecreatingFile: false, warning: .show(.restartFailed))
            ),
            ("healthy", [sample(100, 100), sample(200, 200)], .init(warning: .clear)),
        ]
        for (name, ticks, expected) in cases {
            var watch = MicHealthWatch()
            let verdicts = ticks.map { watch.tick($0) }
            #expect(verdicts.last == expected, "\(name)")
        }
    }

    @Test func systemVerdicts() {
        let failed = sample(500, 1000, failed: true)
        let cases: [(String, [(ChannelSample, TimeInterval)], SystemHealthWatch.Verdict)] = [
            ("not saved", [(sample(100, 0), 5), (sample(200, 0), 10)], .init(issue: .notSaved)),
            // Regression: the permission message fired ~8 s in whenever nothing had played.
            ("missing under 2 min", [(sample(0, 0), 5), (sample(0, 0), 115)], .init()),
            ("missing for 2 min", [(sample(0, 0), 5), (sample(0, 0), 120)], .init(issue: .missing)),
            ("tap failed", [(failed, 5)], .init(restartTap: true, issue: .tapRetrying)),
            (
                "tap failed past the bound", Array(repeating: (failed, 5), count: 4),
                .init(issue: .tapFailed)
            ),
        ]
        for (name, ticks, expected) in cases {
            var watch = SystemHealthWatch()
            let verdicts = ticks.map { watch.tick($0.0, elapsed: $0.1) }
            #expect(verdicts.last == expected, "\(name)")
        }
    }

#if DEBUG
    @Test func micStartThatThrowsIsRecordedAsFailed() throws {
        let session = RecordingSession(
            meetingID: "start-failure", directory: FileManager.default.temporaryDirectory
        ) { _, _ in }
        struct StartError: Error {}
        #expect(throws: StartError.self) {
            try session.recordMicStartForTesting { throw StartError() }
        }
        #expect(session.micStartFailed)
        try session.recordMicStartForTesting {}
        #expect(!session.micStartFailed)
    }
#endif
}
