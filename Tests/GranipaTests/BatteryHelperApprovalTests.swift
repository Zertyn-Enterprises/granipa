import Foundation
import ServiceManagement
import Testing

@testable import Granipa

@MainActor
private final class ApprovalFlowSpy {
    var status: SMAppService.Status = .notRegistered
    var registerError: (any Error)?
    private(set) var openApprovalCount = 0

    func makeLifecycle() -> BatteryHelperServiceLifecycle {
        BatteryHelperServiceLifecycle(
            status: { [weak self] in self?.status ?? .notRegistered },
            unregister: { [weak self] in self?.status = .notRegistered },
            register: { [weak self] in
                if let registerError = self?.registerError { throw registerError }
                self?.status = .enabled
            },
            openApproval: { [weak self] in self?.openApprovalCount += 1 }
        )
    }
}

@MainActor
struct BatteryHelperApprovalTests {

    private func smApprovalCodeOneError() -> NSError {
        NSError(domain: SMAppServiceErrorDomain, code: 1)
    }

    /// SM domain code 1 from register must open approval exactly once even while
    /// status is still .notRegistered, and install must report .needsApproval.
    @Test
    func installSMCodeOneRoutesToApprovalDespiteNotRegisteredStatus() throws {
        let spy = ApprovalFlowSpy()
        spy.registerError = smApprovalCodeOneError()
        let client = BatteryHelperClient()

        let outcome = try client.registerSMAppService(spy.makeLifecycle())

        #expect(outcome == .needsApproval)
        #expect(spy.openApprovalCount == 1)
        #expect(spy.status == .notRegistered)
    }

    /// The same approval error during repair must surface as BatteryHelperError.needsApproval.
    @Test
    func repairSMCodeOneThrowsNeedsApprovalDespiteNotRegisteredStatus() async {
        let spy = ApprovalFlowSpy()
        spy.registerError = smApprovalCodeOneError()
        let client = BatteryHelperClient()

        await #expect(throws: BatteryHelperError.needsApproval) {
            try await client.performRepair(spy.makeLifecycle())
        }

        #expect(spy.openApprovalCount == 1)
    }

    /// The register error must win over a stale .enabled status: never a false .enabled.
    @Test
    func installSMCodeOneWinsOverStaleEnabledStatus() throws {
        let spy = ApprovalFlowSpy()
        spy.registerError = smApprovalCodeOneError()
        spy.status = .enabled
        let client = BatteryHelperClient()

        let outcome = try client.registerSMAppService(spy.makeLifecycle())

        #expect(outcome == .needsApproval)
        #expect(outcome != .enabled)
        #expect(spy.openApprovalCount == 1)
    }

    /// kSMErrorLaunchDeniedByUser also routes to approval, even while not registered.
    @Test
    func repairLaunchDeniedByUserRoutesToApprovalWhenNotRegistered() async {
        let spy = ApprovalFlowSpy()
        spy.registerError = NSError(domain: SMAppServiceErrorDomain, code: Int(kSMErrorLaunchDeniedByUser))
        let client = BatteryHelperClient()

        await #expect(throws: BatteryHelperError.needsApproval) {
            try await client.performRepair(spy.makeLifecycle())
        }

        #expect(spy.openApprovalCount == 1)
    }

    /// A non-SM error must never trigger approval or a needsApproval/enabled outcome during install;
    /// returning nil or throwing the underlying error is acceptable.
    @Test
    func installUnrelatedCocoaErrorNeverClaimsApproval() {
        let spy = ApprovalFlowSpy()
        spy.registerError = NSError(domain: NSCocoaErrorDomain, code: 1)
        let client = BatteryHelperClient()

        var outcome: BatteryHelperInstallOutcome?
        var thrownError: (any Error)?
        do {
            outcome = try client.registerSMAppService(spy.makeLifecycle())
        } catch {
            thrownError = error
        }

        if let thrownError {
            #expect((thrownError as? BatteryHelperError) != .needsApproval)
        } else if let outcome {
            #expect(outcome != .needsApproval)
            #expect(outcome != .enabled)
        }
        #expect(spy.openApprovalCount == 0)
    }

    /// Repair on a non-SM error must throw BatteryHelperError.install retaining
    /// the underlying localized description, without opening approval.
    @Test
    func repairUnrelatedCocoaErrorWrapsUnderlyingDescriptionWithoutApproval() async {
        let underlying = NSError(domain: NSCocoaErrorDomain, code: 1)
        let spy = ApprovalFlowSpy()
        spy.registerError = underlying
        let client = BatteryHelperClient()

        do {
            try await client.performRepair(spy.makeLifecycle())
            Issue.record("Expected performRepair to throw BatteryHelperError.install")
        } catch let helperError as BatteryHelperError {
            guard case let .install(message) = helperError else {
                Issue.record("Expected BatteryHelperError.install, got \(helperError)")
                return
            }
            #expect(message.contains(underlying.localizedDescription))
        } catch {
            Issue.record("Expected BatteryHelperError.install wrapping underlying error, got \(error)")
        }

        #expect(spy.openApprovalCount == 0)
    }
}
