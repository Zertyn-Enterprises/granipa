import ServiceManagement
import os

/// Battery control was removed (macOS 27 blocks the SMC charge keys and has a
/// native charge limit). Earlier V2 builds could register a root daemon through
/// SMAppService; its plist and a no-op stub executable stay bundled only so that
/// registration still resolves and can be unregistered here.
enum LegacyBatteryHelper {
    static let plistName = "com.zertyn.granipa.batteryhelper.plist"
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "legacy-battery")

    static func needsUnregister(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    static func unregisterIfRegistered(
        status: () -> SMAppService.Status = {
            SMAppService.daemon(plistName: plistName).status
        },
        unregister: (@escaping @Sendable (Error?) -> Void) -> Void = {
            SMAppService.daemon(plistName: plistName).unregister(completionHandler: $0)
        }
    ) {
        guard needsUnregister(status()) else { return }
        unregister { error in
            if let error {
                log.error("legacy battery helper unregister failed: \(error.localizedDescription, privacy: .public)")
            } else {
                log.info("legacy battery helper unregistered")
            }
        }
    }
}
