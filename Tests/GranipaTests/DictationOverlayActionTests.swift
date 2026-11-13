import Testing

@testable import Granipa

@Suite struct DictationOverlayActionTests {
    @Test func liveSessionsOfferCancel() {
        #expect(DictationOverlayAction.available(for: .preparing, retryable: false) == [.cancel])
        #expect(DictationOverlayAction.available(for: .listening, retryable: false) == [.cancel])
    }

    @Test func retryableFailureCanBeRetriedOrDismissed() {
        #expect(
            DictationOverlayAction.available(for: .failed("x"), retryable: true)
                == [.retry, .dismiss])
    }

    @Test func settledStatesOfferNothing() {
        // Non-retryable failures and Pasted hide on their own.
        #expect(DictationOverlayAction.available(for: .failed("x"), retryable: false).isEmpty)
        #expect(DictationOverlayAction.available(for: .done, retryable: false).isEmpty)
        #expect(DictationOverlayAction.available(for: .processing, retryable: false).isEmpty)
        #expect(DictationOverlayAction.available(for: .idle, retryable: false).isEmpty)
    }
}
