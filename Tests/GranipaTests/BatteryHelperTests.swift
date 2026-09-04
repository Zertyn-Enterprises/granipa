import Foundation
import Testing

@testable import Granipa

@Suite struct BatteryHelperTests {
    @Test func helperAcceptsOnlyTheSignedGranipaTeam() {
        let requirement = BatteryHelperSecurity.clientRequirement
        #expect(requirement.contains(#"identifier "com.zertyn.granipa""#))
        #expect(requirement.contains("anchor apple generic"))
        #expect(requirement.contains("R4V252C833"))
    }

    @Test func bundledDaemonRunsOnlyOnDemand() throws {
        let source = URL(fileURLWithPath: #filePath)
        let repo = source.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: repo.appendingPathComponent(
                "Resources/com.zertyn.granipa.batteryhelper.plist"))
        let raw = try PropertyListSerialization.propertyList(from: data, format: nil)
        let plist = try #require(raw as? [String: Any])
        #expect(plist["RunAtLoad"] == nil)
        #expect(plist["KeepAlive"] == nil)
        #expect(plist["MachServices"] != nil)
    }

    @Test func errorCopy() {
        #expect(BatteryHelperError.missingBinary.errorDescription?.contains("bundle.sh") == true)
        #expect(BatteryHelperError.needsApproval.errorDescription?.contains("Login Items") == true)
        #expect(BatteryHelperError.install("nope").errorDescription == "nope")
    }

    @Test func helperActionRawValues() {
        #expect(ChargeAction.charge.helperRaw == 0)
        #expect(ChargeAction.inhibit.helperRaw == 1)
        #expect(ChargeAction.discharge.helperRaw == 2)
    }

    @Test func smcWireLayoutMatchesTheKernelABI() {
        #expect(MemoryLayout<SMCParamStruct>.size == 80)
        #expect(MemoryLayout<SMCParamStruct>.stride == 80)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.dataSize) == 28)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.dataAttributes) == 36)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.padding) == 38)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.result) == 40)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data8) == 42)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.data32) == 44)
        #expect(MemoryLayout<SMCParamStruct>.offset(of: \.b0) == 48)
    }

    @Test func xpcReplyReturnsToMainActor() async {
        let delivered: Bool = await withCheckedContinuation {
            (continuation: CheckedContinuation<Bool, Never>) in
            let reply = BatteryHelperCallbacks.mainActor { ok, _ in
                MainActor.preconditionIsolated()
                continuation.resume(returning: ok)
            }
            DispatchQueue.global().async {
                reply(true, nil)
            }
        }
        #expect(delivered)
    }

    @Test func xpcErrorPreservesMessageOnMainActor() async {
        let delivered: (Bool, String?) = await withCheckedContinuation {
            (continuation: CheckedContinuation<(Bool, String?), Never>) in
            let reply = BatteryHelperCallbacks.mainActor { ok, message in
                MainActor.preconditionIsolated()
                continuation.resume(returning: (ok, message))
            }
            let handler = BatteryHelperCallbacks.error(reply)
            DispatchQueue.global().async {
                handler(NSError(domain: "BatteryHelperTests", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "expected"
                ]))
            }
        }
        #expect(!delivered.0)
        #expect(delivered.1 == "expected")
    }

    @Test func synchronousResultTimesOut() {
        let result = BatteryHelperResultLatch()
        #expect(!result.wait(timeout: 0))
    }

    @Test func synchronousResultKeepsFirstReply() {
        let result = BatteryHelperResultLatch()
        result.resolve(true)
        result.resolve(false)
        #expect(result.wait(timeout: 0))
    }
}
