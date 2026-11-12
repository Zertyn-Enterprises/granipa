import Darwin
import Foundation
import os

let batteryHelperMachName = "com.zertyn.granipa.batteryhelper"
private let clientRequirement =
    "anchor apple generic and identifier \"com.zertyn.granipa\" "
    + "and certificate leaf[subject.OU] = \"R4V252C833\""
private let log = Logger(subsystem: "com.zertyn.granipa.batteryhelper", category: "helper")

@objc
protocol GranipaBatteryHelping {
    func applyAction(_ raw: Int, usingCHTE: Bool, reply: @escaping (Bool, String?) -> Void)
    func applyLED(_ value: UInt8, reply: @escaping (Bool, String?) -> Void)
}

final class BatteryHelperService: NSObject, GranipaBatteryHelping, @unchecked Sendable {
    private let smc = HelperSMC()
    private let lock = NSLock()
    private var lastUsingCHTE = false
    private var served = false

    /// True once this connection delivered a message, which the code-signing
    /// requirement only lets the signed app do.
    var didServe: Bool {
        lock.lock()
        defer { lock.unlock() }
        return served
    }

    func applyAction(_ raw: Int, usingCHTE: Bool, reply: @escaping (Bool, String?) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        served = true
        do {
            switch raw {
            case 0:  // ChargeAction.charge.helperRaw
                try setCharging(true, usingCHTE: usingCHTE)
                try setDischarge(false)
            case 1:  // ChargeAction.inhibit.helperRaw
                try setCharging(false, usingCHTE: usingCHTE)
                try setDischarge(false)
            case 2:  // ChargeAction.discharge.helperRaw
                try setCharging(false, usingCHTE: usingCHTE)
                try setDischarge(true)
            default:
                reply(false, "Unknown action")
                return
            }
            lastUsingCHTE = usingCHTE
            log.info("applyAction \(raw, privacy: .public) ok")
            reply(true, nil)
        } catch {
            log.error("applyAction \(raw, privacy: .public) \(error.localizedDescription, privacy: .public)")
            reply(false, error.localizedDescription)
        }
    }

    func applyLED(_ value: UInt8, reply: @escaping (Bool, String?) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        served = true
        do {
            try smc.writeU8("ACLC", value)
            log.info("applyLED \(value, privacy: .public) ok")
            reply(true, nil)
        } catch {
            log.error("applyLED \(error.localizedDescription, privacy: .public)")
            reply(false, error.localizedDescription)
        }
    }

    func restoreDefaults() {
        lock.lock()
        defer { lock.unlock() }
        do {
            try setCharging(true, usingCHTE: lastUsingCHTE)
            try setDischarge(false)
            if smc.keyExists("ACLC") { try smc.writeU8("ACLC", 0) }
            log.info("restored charging after client disconnect")
        } catch {
            log.error("restore after disconnect failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func setCharging(_ on: Bool, usingCHTE: Bool) throws {
        if usingCHTE {
            try smc.writeU32LE("CHTE", on ? 0 : 1)
        } else {
            let byte: UInt8 = on ? 0x00 : 0x02
            try smc.writeU8("CH0B", byte)
            if smc.keyExists("CH0C") { try smc.writeU8("CH0C", byte) }
        }
    }

    private func setDischarge(_ on: Bool) throws {
        if smc.keyExists("CH0I") {
            try smc.writeU8("CH0I", on ? 1 : 0)
        } else if smc.keyExists("CHIE") {
            try smc.writeU8("CHIE", on ? 8 : 0)
        } else if on {
            throw HelperSMCError.failed
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection)
        -> Bool
    {
        let service = BatteryHelperService()
        connection.setCodeSigningRequirement(clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: GranipaBatteryHelping.self)
        connection.exportedObject = service
        // A caller that fails the code-signing requirement can still connect
        // and drop; only the app's own connection may end the charge limit.
        connection.invalidationHandler = {
            guard service.didServe else { return }
            service.restoreDefaults()
            exit(EXIT_SUCCESS)
        }
        connection.resume()
        return true
    }
}

// HelperSMCParam is a copy of the app's SMCParamStruct; if its layout drifts
// from the kernel ABI, stop before any SMC write rather than send garbage.
precondition(
    MemoryLayout<HelperSMCParam>.stride == 80
        && MemoryLayout<HelperSMCParam>.offset(of: \.dataSize) == 28
        && MemoryLayout<HelperSMCParam>.offset(of: \.result) == 40
        && MemoryLayout<HelperSMCParam>.offset(of: \.data8) == 42
        && MemoryLayout<HelperSMCParam>.offset(of: \.b0) == 48,
    "HelperSMCParam does not match the 80-byte AppleSMC parameter layout")
log.info("listening stride=\(MemoryLayout<HelperSMCParam>.stride, privacy: .public)")
let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: batteryHelperMachName)
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
