import Testing

@testable import Granipa

@Suite struct WebhookDeliveryTests {
    actor Passes {
        private(set) var count = 0
        func start() -> Int {
            count += 1
            return count
        }
    }

    @Test func requestsDuringAPassCauseExactlyOneMorePass() async {
        let flight = SingleFlight()
        let passes = Passes()
        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        let pass: @Sendable () async -> Void = {
            if await passes.start() == 1 {
                for await _ in gate {}
            }
        }

        let first = Task { await flight.run(pass) }
        while await passes.count == 0 { await Task.yield() }
        // Both return at once instead of starting a parallel pass.
        await flight.run(pass)
        await flight.run(pass)
        #expect(await passes.count == 1)
        release.finish()
        await first.value

        #expect(await passes.count == 2)
        await flight.run(pass)
        #expect(await passes.count == 3)
    }
}
