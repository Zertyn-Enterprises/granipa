import AppKit
import Foundation
import ServiceManagement

/// Injected SMAppService boundary so focused tests can observe the
/// unregister→register lifecycle without touching real service registration.
@MainActor
struct BatteryHelperServiceLifecycle: Sendable {
    let status: @MainActor @Sendable () -> SMAppService.Status
    let unregister: @MainActor @Sendable () async throws -> Void
    let register: @MainActor @Sendable () throws -> Void
    let openApproval: @MainActor @Sendable () -> Void

    static let live = Self(
        status: { SMAppService.daemon(plistName: batteryHelperPlistName).status },
        unregister: {
            try await SMAppService.daemon(plistName: batteryHelperPlistName).unregister()
        },
        register: { try SMAppService.daemon(plistName: batteryHelperPlistName).register() },
        openApproval: { SMAppService.openSystemSettingsLoginItems() })
}

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
        try validateHelperBundle(performing: "installing")
        resetConnection()
        invalidateStatusCache()
        if let outcome = try registerSMAppService(BatteryHelperServiceLifecycle.live) {
            return outcome
        }
        throw BatteryHelperError.install("macOS could not register the battery helper.")
    }

    /// Repair replaces a possibly broken registration: unregister whatever
    /// macOS holds, then register the current bundle. A register failure
    /// surfaces the underlying error; "not registered" is claimed only when
    /// a status check confirmed it.
    func repair() async throws {
        try validateHelperBundle(performing: "repairing")
        resetConnection()
        defer { invalidateStatusCache() }
        try await performRepair(BatteryHelperServiceLifecycle.live)
    }

    func performRepair(_ lifecycle: BatteryHelperServiceLifecycle) async throws {
        switch lifecycle.status() {
        case .notRegistered, .notFound:
            break
        default:
            do {
                try await lifecycle.unregister()
            } catch {
                throw BatteryHelperError.install(
                    "Could not remove the previous battery helper registration: \(error.localizedDescription)")
            }
        }
        do {
            try lifecycle.register()
        } catch {
            if lifecycle.status() == .requiresApproval {
                lifecycle.openApproval()
                throw BatteryHelperError.needsApproval
            }
            throw BatteryHelperError.install(
                "Repair failed: \(error.localizedDescription)")
        }
        switch lifecycle.status() {
        case .enabled:
            return
        case .requiresApproval:
            lifecycle.openApproval()
            throw BatteryHelperError.needsApproval
        case .notRegistered, .notFound:
            throw Self.repairNotRegistered
        @unknown default:
            throw BatteryHelperError.install(
                "Repair failed — macOS reported an unknown registration state. Try again.")
        }
    }

    /// Thrown only where a status check confirmed the registration is gone.
    private static let repairNotRegistered = BatteryHelperError.install(
        "Repair failed — the battery helper is not registered. Try again.")

    private func validateHelperBundle(performing action: String) throws {
        guard helperBinaryURL != nil else { throw BatteryHelperError.missingBinary }
        guard Bundle.main.bundleURL.path.hasPrefix("/Applications/") else {
            throw BatteryHelperError.install(
                "Move Grañipa to Applications before \(action) the battery helper.")
        }
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

    func registerSMAppService(
        _ lifecycle: BatteryHelperServiceLifecycle
    ) throws -> BatteryHelperInstallOutcome? {
        do {
            try lifecycle.register()
        } catch {
            if lifecycle.status() == .enabled {
                return .enabled
            }
            if lifecycle.status() == .requiresApproval {
                lifecycle.openApproval()
                return .needsApproval
            }
            return nil
        }
        switch lifecycle.status() {
        case .enabled:
            return .enabled
        case .requiresApproval:
            lifecycle.openApproval()
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
