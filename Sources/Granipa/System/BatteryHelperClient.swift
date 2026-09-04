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

    func apply(
        action: ChargeAction,
        usingCHTE: Bool,
        reply: @escaping @MainActor @Sendable (Bool, String?) -> Void
    ) {
        let deliver = BatteryHelperCallbacks.mainActor(reply)
        guard let proxy = proxy(errorHandler: BatteryHelperCallbacks.error(deliver)) else { return }
        proxy.applyAction(action.helperRaw, usingCHTE: usingCHTE, reply: deliver)
    }

    func applyLED(
        _ value: UInt8,
        reply: @escaping @MainActor @Sendable (Bool, String?) -> Void
    ) {
        let deliver = BatteryHelperCallbacks.mainActor(reply)
        guard let proxy = proxy(errorHandler: BatteryHelperCallbacks.error(deliver)) else { return }
        proxy.applyLED(value, reply: deliver)
    }

    func applySynchronously(
        action: ChargeAction,
        usingCHTE: Bool,
        timeout: TimeInterval = 1
    ) -> Bool {
        let result = BatteryHelperResultLatch()
        let deliver = BatteryHelperCallbacks.latch(result)
        guard let proxy = proxy(errorHandler: BatteryHelperCallbacks.error(deliver)) else {
            return false
        }
        proxy.applyAction(action.helperRaw, usingCHTE: usingCHTE, reply: deliver)
        return result.wait(timeout: timeout)
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

    private func proxy(errorHandler: @escaping @Sendable (Error) -> Void)
        -> GranipaBatteryHelping?
    {
        if connection == nil {
            // LaunchDaemons live in the system bootstrap, not the user one.
            let conn = NSXPCConnection(
                machServiceName: batteryHelperMachName, options: .privileged)
            conn.remoteObjectInterface = NSXPCInterface(with: GranipaBatteryHelping.self)
            conn.invalidationHandler = BatteryHelperCallbacks.mainActor { [weak self] in
                self?.connection = nil
            }
            conn.resume()
            connection = conn
        }
        guard
            let proxy = connection?.remoteObjectProxyWithErrorHandler(errorHandler)
                as? GranipaBatteryHelping
        else {
            errorHandler(BatteryHelperError.install("Battery helper is not connected."))
            return nil
        }
        return proxy
    }
}

enum BatteryHelperCallbacks {
    typealias Reply = @Sendable (Bool, String?) -> Void

    static func mainActor(
        _ reply: @escaping @MainActor @Sendable (Bool, String?) -> Void
    ) -> Reply {
        { ok, error in
            Task { @MainActor in
                reply(ok, error)
            }
        }
    }

    static func mainActor(
        _ action: @escaping @MainActor @Sendable () -> Void
    ) -> @Sendable () -> Void {
        {
            Task { @MainActor in
                action()
            }
        }
    }

    static func error(_ reply: @escaping Reply) -> @Sendable (Error) -> Void {
        { error in
            reply(false, error.localizedDescription)
        }
    }

    fileprivate static func latch(_ result: BatteryHelperResultLatch) -> Reply {
        { ok, _ in
            result.resolve(ok)
        }
    }
}

final class BatteryHelperResultLatch: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var result: Bool?

    func resolve(_ value: Bool) {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return
        }
        result = value
        lock.unlock()
        semaphore.signal()
    }

    func wait(timeout: TimeInterval) -> Bool {
        guard semaphore.wait(timeout: .now() + timeout) == .success else { return false }
        lock.lock()
        defer { lock.unlock() }
        return result ?? false
    }
}
