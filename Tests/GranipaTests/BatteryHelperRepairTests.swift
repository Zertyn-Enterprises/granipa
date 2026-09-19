import Foundation
import ServiceManagement
import Testing

@testable import Granipa

/// The lifecycle spy only replaces the SMAppService calls, never the
/// bundle/binary guards — those run for real in the test host.
@Suite struct BatteryHelperRepairTests {
    @MainActor
    @Test func installRegistersWithoutUnregistering() throws {
        let spy = HelperLifecycleSpy()
        let outcome = try BatteryHelperClient().registerSMAppService(spy.lifecycle)
        #expect(outcome == .enabled)
        #expect(spy.calls.filter { $0 == "unregister" || $0 == "register" } == ["register"])
    }

    @MainActor
    @Test func repairUnregistersExistingServiceBeforeRegistering() async throws {
        let spy = HelperLifecycleSpy()
        try await BatteryHelperClient().performRepair(spy.lifecycle)
        #expect(
            spy.calls.filter { $0 == "unregister" || $0 == "register" }
                == ["unregister", "register"])
    }

    @MainActor
    @Test func repairOnUnregisteredServiceSkipsUnregister() async throws {
        let spy = HelperLifecycleSpy()
        spy.status = .notRegistered
        try await BatteryHelperClient().performRepair(spy.lifecycle)
        #expect(spy.calls.filter { $0 == "unregister" || $0 == "register" } == ["register"])
    }

    @MainActor
    @Test func repairSkipsRegisterWhenUnregisterFails() async {
        let spy = HelperLifecycleSpy()
        spy.unregisterError = BatteryHelperError.install("launchd refused")
        await #expect(throws: BatteryHelperError.self) {
            try await BatteryHelperClient().performRepair(spy.lifecycle)
        }
        #expect(!spy.calls.contains("register"))
    }

    /// A register failure surfaces the underlying error; the registration
    /// state after the throw is unknown, so no "not registered" claim is made.
    @MainActor
    @Test func repairRegisterFailurePropagatesUnderlyingError() async {
        let spy = HelperLifecycleSpy()
        spy.registerError = BatteryHelperError.install("launchd refused")
        await #expect(
            throws: BatteryHelperError.install("Repair failed: launchd refused")
        ) {
            try await BatteryHelperClient().performRepair(spy.lifecycle)
        }
        #expect(
            spy.calls.filter { $0 == "unregister" || $0 == "register" }
                == ["unregister", "register"])
    }

    @MainActor
    @Test func repairSuccessReturnsQuietly() async throws {
        let spy = HelperLifecycleSpy()
        try await BatteryHelperClient().performRepair(spy.lifecycle)
        #expect(!spy.calls.contains("openApproval"))
    }

    /// Register succeeded and the post-register status still asks for approval.
    @MainActor
    @Test func repairApprovalRequiredThrowsAndOpensLoginItems() async {
        let spy = HelperLifecycleSpy()
        spy.status = .requiresApproval
        spy.statusAfterRegister = .requiresApproval
        await #expect(throws: BatteryHelperError.needsApproval) {
            try await BatteryHelperClient().performRepair(spy.lifecycle)
        }
        #expect(spy.calls.contains("openApproval"))
    }

    /// Register itself threw while the service sits in requiresApproval —
    /// distinct from the successful-register approval path above.
    @MainActor
    @Test func repairRegisterThrowWithRequiresApprovalOpensLoginItems() async {
        let spy = HelperLifecycleSpy()
        spy.registerError = BatteryHelperError.install("denied")
        spy.statusWhenRegisterThrows = .requiresApproval
        await #expect(throws: BatteryHelperError.needsApproval) {
            try await BatteryHelperClient().performRepair(spy.lifecycle)
        }
        #expect(spy.calls.contains("openApproval"))
    }

    /// The production guards run for real in the test host: its bundle has no
    /// bundled helper binary, so repair must refuse before touching SMAppService.
    @MainActor
    @Test func repairKeepsProductionBundleGuards() async {
        await #expect(throws: BatteryHelperError.missingBinary) {
            try await BatteryHelperClient.shared.repair()
        }
    }

    @MainActor
    @Test func repairHelperShowsFailureThenRegisteredOnRetry() async {
        let battery = BatteryService()
        battery.performHelperRepair = {
            throw BatteryHelperError.install("Repair failed: launchd refused")
        }
        await battery.repairHelper()
        #expect(battery.controlMessage == "Repair failed: launchd refused")
        #expect(battery.helperBusy == false)
        battery.performHelperRepair = {}
        await battery.repairHelper()
        #expect(battery.controlMessage == "Battery helper registered.")
    }

    @MainActor
    @Test func secondRepairClickWhileBusyIsIgnored() async {
        let battery = BatteryService()
        let gate = RepairGate()
        battery.performHelperRepair = { try await gate.run() }
        async let first: Void = battery.repairHelper()
        var spins = 0
        while gate.entries == 0 {
            guard spins < 10_000 else {
                Issue.record("first repair never started; busy guard untestable")
                return
            }
            spins += 1
            await Task.yield()
        }
        #expect(battery.controlMessage == "Repairing the battery helper…")
        await battery.repairHelper()
        #expect(gate.entries == 1)
        #expect(battery.helperBusy == true)
        gate.finish()
        _ = await first
        #expect(battery.helperBusy == false)
    }
}

@MainActor
private final class HelperLifecycleSpy {
    var status: SMAppService.Status = .enabled
    var statusAfterRegister: SMAppService.Status = .enabled
    var statusWhenRegisterThrows: SMAppService.Status = .notRegistered
    var unregisterError: Error?
    var registerError: Error?
    private(set) var calls: [String] = []

    var lifecycle: BatteryHelperServiceLifecycle {
        .init(
            status: { self.status },
            unregister: {
                self.calls.append("unregister")
                if let error = self.unregisterError { throw error }
                self.status = .notRegistered
            },
            register: {
                self.calls.append("register")
                if let error = self.registerError {
                    self.status = self.statusWhenRegisterThrows
                    throw error
                }
                self.status = self.statusAfterRegister
            },
            openApproval: { self.calls.append("openApproval") })
    }
}

@MainActor
private final class RepairGate {
    private(set) var entries = 0
    private var waiting: CheckedContinuation<Void, Never>?

    func run() async throws {
        entries += 1
        await withTaskCancellationHandler {
            await withCheckedContinuation { waiting = $0 }
        } onCancel: {
            // Scope exit cancels an un-awaited async-let child; the parked
            // continuation must resume or the test hangs.
            Task { @MainActor in self.finish() }
        }
    }

    func finish() {
        waiting?.resume()
        waiting = nil
    }
}
