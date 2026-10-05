import ServiceManagement
import os

/// Battery control was removed (macOS 27 blocks the SMC charge keys and has a
/// native charge limit). Earlier V2 builds could register a root daemon through
/// SMAppService; its plist stays bundled only so that registration can be
/// resolved and unregistered here.
enum LegacyBatteryHelper {
    static let plistName = "com.zertyn.granipa.batteryhelper.plist"
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "legacy-battery")

    static func needsUnregister(_ status: SMAppService.Status) -> Bool {
        status == .enabled || status == .requiresApproval
    }

    static func unregisterIfRegistered() {
        let service = SMAppService.daemon(plistName: plistName)
        guard needsUnregister(service.status) else { return }
        service.unregister { error in
            if let error {
                log.error("legacy battery helper unregister failed: \(error.localizedDescription, privacy: .public)")
            } else {
                log.info("legacy battery helper unregistered")
            }
        }
    }
}
