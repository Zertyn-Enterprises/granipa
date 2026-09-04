import Testing

@testable import Granipa

@Suite struct SystemTapRetryPolicyTests {
    @Test func retriesOnlyWhileNoBufferHasEverArrived() {
        #expect(SystemTapRetryPolicy.shouldRetry(bufferCount: 0, attempts: 0))
        #expect(!SystemTapRetryPolicy.shouldRetry(bufferCount: 0, attempts: 1))
        #expect(!SystemTapRetryPolicy.shouldRetry(bufferCount: 1, attempts: 0))
        #expect(!SystemTapRetryPolicy.shouldRetry(bufferCount: 100, attempts: 0))
    }
}
