import Foundation

let batteryHelperMachName = "com.zertyn.granipa.batteryhelper"
let batteryHelperPlistName = "com.zertyn.granipa.batteryhelper.plist"

enum BatteryHelperSecurity {
    static let teamIdentifier = "R4V252C833"
    static let clientRequirement =
        "anchor apple generic and identifier \"com.zertyn.granipa\" "
        + "and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
}

enum BatteryHelperInstallOutcome: Equatable, Sendable {
    case enabled
    case needsApproval
}

enum BatteryHelperError: LocalizedError, Equatable {
    case missingBinary
    case needsApproval
    case install(String)

    var errorDescription: String? {
        switch self {
        case .missingBinary:
            "GranipaBatteryHelper is missing from the app bundle. Rebuild with Scripts/bundle.sh."
        case .needsApproval:
            "Turn on Grañipa in System Settings → General → Login Items, then toggle Limit charging again."
        case .install(let message):
            message
        }
    }
}

@objc
protocol GranipaBatteryHelping {
    func applyAction(_ raw: Int, usingCHTE: Bool, reply: @escaping (Bool, String?) -> Void)
    func applyLED(_ value: UInt8, reply: @escaping (Bool, String?) -> Void)
}
