import AppKit
import Foundation
import ServiceManagement

@MainActor
final class BatteryHelperClient {
    static let shared = BatteryHelperClient()
    private var connection: NSXPCConnection?
    private var cachedSMAppServiceEnabled: Bool?
    private var lastStatusCheck = Date.distantPast

    var status: SMAppService.Status {
        SMAppService.daemon(plistName: batteryHelperPlistName).status
    }

    var isEnabled: Bool {
        if let cachedSMAppServiceEnabled,
            Date.now.timeIntervalSince(lastStatusCheck) < 60
        {
            return cachedSMAppServiceEnabled
        }
        let enabled = status == .enabled
        cachedSMAppServiceEnabled = enabled
        lastStatusCheck = .now
        return enabled
    }

    func invalidateStatusCache() {
        cachedSMAppServiceEnabled = nil
        lastStatusCheck = .distantPast
    }

    var helperBinaryURL: URL? {
        let url = Bundle.main.bundleURL.appendingPathComponent(
            "Contents/MacOS/GranipaBatteryHelper")
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    func install() throws -> BatteryHelperInstallOutcome {
        guard helperBinaryURL != nil else { throw BatteryHelperError.missingBinary }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            throw BatteryHelperError.install(
                "Move Grañipa to Applications before installing the battery helper.")
        }
        resetConnection()
        invalidateStatusCache()
        if let outcome = try registerSMAppService() {
            return outcome
        }
        throw BatteryHelperError.install("macOS could not register the battery helper.")
    }

    func apply(action: ChargeAction, usingCHTE: Bool, reply: @escaping (Bool, String?) -> Void) {
        guard let proxy = proxy(reply: reply) else { return }
        proxy.applyAction(action.helperRaw, usingCHTE: usingCHTE, reply: reply)
    }

    func applyLED(_ value: UInt8, reply: @escaping (Bool, String?) -> Void) {
        guard let proxy = proxy(reply: reply) else { return }
        proxy.applyLED(value, reply: reply)
    }

    func applySynchronously(
        action: ChargeAction,
        usingCHTE: Bool,
        timeout: TimeInterval = 1
    ) -> Bool {
        let completion = DispatchSemaphore(value: 0)
        var succeeded = false
        apply(action: action, usingCHTE: usingCHTE) { ok, _ in
            succeeded = ok
            completion.signal()
        }
        guard completion.wait(timeout: .now() + timeout) == .success else { return false }
        return succeeded
    }

    private func registerSMAppService() throws -> BatteryHelperInstallOutcome? {
        let service = SMAppService.daemon(plistName: batteryHelperPlistName)
        do {
            try service.register()
        } catch {
            if service.status == .enabled {
                return .enabled
            }
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                return .needsApproval
            }
            return nil
        }
        switch service.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            SMAppService.openSystemSettingsLoginItems()
            return .needsApproval
        case .notRegistered, .notFound:
            return nil
        @unknown default:
            return nil
        }
    }

    private func resetConnection() {
        connection?.invalidate()
        connection = nil
    }

    private func proxy(reply: @escaping (Bool, String?) -> Void) -> GranipaBatteryHelping? {
        if connection == nil {
            // LaunchDaemons live in the system bootstrap, not the user one.
            let conn = NSXPCConnection(
                machServiceName: batteryHelperMachName, options: .privileged)
            conn.remoteObjectInterface = NSXPCInterface(with: GranipaBatteryHelping.self)
            conn.invalidationHandler = { [weak self] in
                Task { @MainActor in self?.connection = nil }
            }
            conn.resume()
            connection = conn
        }
        guard
            let proxy = connection?.remoteObjectProxyWithErrorHandler({ error in
                reply(false, error.localizedDescription)
            }) as? GranipaBatteryHelping
        else {
            reply(false, "Battery helper is not connected.")
            return nil
        }
        return proxy
    }
}
