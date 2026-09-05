import Foundation
import Testing

@testable import Granipa

/// The idle Readiness card may show the Apple-locale Language row only when
/// the configured engine is local — the same rule the live Session card
/// applies to `dictation.engineID`.
@Suite struct DictationIdleEngineTests {
    @Test func absentLocalAndUnknownConfigurationsResolveToLocal() {
        #expect(DictationIdleEngine(configuredRaw: nil) == .local)
        #expect(DictationIdleEngine(configuredRaw: "local") == .local)
        #expect(DictationIdleEngine(configuredRaw: "bogus") == .local)
    }

    @Test func configuredMuseSuppressesTheAppleLocaleRow() {
        #expect(DictationIdleEngine(configuredRaw: "muse") == .muse)
    }
}

/// Locale display labels: a localized name plus region when known, the raw
/// identifier otherwise — never an invented language.
@Suite struct InspectorFormatTests {
    @Test func languageLabelNamesTheLanguageAndRegion() {
        let label = InspectorFormat.languageLabel(forIdentifier: "es-ES")
        #expect(label.hasSuffix("(ES)"))
        #expect(!label.contains("es-ES"), "the raw identifier is not a display label")
    }

    @Test func languageLabelWithoutRegionOmitsTheParenthesis() {
        let label = InspectorFormat.languageLabel(forIdentifier: "en")
        #expect(!label.contains("("))
        #expect(!label.isEmpty)
    }

    @Test func autoAndUnknownIdentifiersStayTruthful() {
        #expect(InspectorFormat.languageLabel(forIdentifier: "auto") == "Auto")
        #expect(InspectorFormat.languageLabel(forIdentifier: "") == "Auto")
        #expect(InspectorFormat.languageLabel(forIdentifier: "zzz-QQ") == "zzz-QQ")
    }
}

/// The live inspector's elapsed clock runs inside `.task(id: phase)`, which
/// SwiftUI cancels when the view disappears — while the app-scoped
/// controller can still be `.listening`. A `wait` that swallows cancellation
/// turns that into an infinite busy loop, so cancellation must become an
/// explicit "stop ticking".
@Suite struct DictationLiveTickerTests {
    @Test func cancelledWaitReportsStop() async {
        let task = Task { await DictationLiveTicker.wait(interval: .seconds(30)) }
        task.cancel()
        let started = Date.now
        let shouldContinue = await task.value
        #expect(!shouldContinue)
        #expect(Date.now.timeIntervalSince(started) < 1)
    }

    @Test func nonCancelledWaitReportsContinue() async {
        let shouldContinue = await DictationLiveTicker.wait(interval: .milliseconds(5))
        #expect(shouldContinue)
    }

    private actor TickCounter {
        var count = 0
        func tick() { count += 1 }
    }

    private actor AlwaysActive {
        var active = true
    }

    @Test func tickerLoopBuiltOnWaitStopsAfterCancellation() async throws {
        // The shape of the inspector loop: tick, wait, repeat while active.
        let counter = TickCounter()
        let active = AlwaysActive()
        let task = Task {
            while await active.active {
                await counter.tick()
                guard await DictationLiveTicker.wait(interval: .milliseconds(10)) else {
                    break
                }
            }
        }
        try await Task.sleep(for: .milliseconds(60))
        let atCancel = await counter.count
        #expect(atCancel >= 1)

        task.cancel()
        try await Task.sleep(for: .milliseconds(150))
        let after = await counter.count
        #expect(after - atCancel <= 1, "ticking must stop once the task is cancelled")
    }
}
