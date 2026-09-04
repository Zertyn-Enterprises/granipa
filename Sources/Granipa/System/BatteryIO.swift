import Foundation
import IOKit.ps

struct BatterySnapshot: Equatable, Sendable {
    var isPresent: Bool
    var percent: Int
    var isCharging: Bool
    var isPluggedIn: Bool
    /// Minutes until empty. Nil if unknown or charging.
    var minutesToEmpty: Int?

    static let missing = BatterySnapshot(
        isPresent: false, percent: 0, isCharging: false, isPluggedIn: false, minutesToEmpty: nil)

    var menuBarText: String {
        if let minutes = minutesToEmpty, minutes > 0, !isCharging {
            let hours = minutes / 60
            let mins = minutes % 60
            if hours > 0 { return "\(hours)h \(mins)m" }
            return "\(mins)m"
        }
        return "\(percent)%"
    }
}

enum BatteryIO {
    static func snapshot() -> BatterySnapshot {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return .missing }

        for source in list {
            guard
                let raw = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any]
            else { continue }
            let type = raw[kIOPSTypeKey] as? String
            guard type == kIOPSInternalBatteryType else { continue }
            let current = raw[kIOPSCurrentCapacityKey] as? Int ?? 0
            let capacity = raw[kIOPSMaxCapacityKey] as? Int ?? 0
            let percent =
                capacity > 0 ? Int((Double(current) / Double(capacity) * 100).rounded()) : current
            let charging = raw[kIOPSIsChargingKey] as? Bool ?? false
            let state = raw[kIOPSPowerSourceStateKey] as? String
            let plugged = state == kIOPSACPowerValue
            let empty = raw[kIOPSTimeToEmptyKey] as? Int
            let minutes = (empty ?? -1) > 0 ? empty : nil
            return BatterySnapshot(
                isPresent: true,
                percent: Swift.min(100, Swift.max(0, percent)),
                isCharging: charging,
                isPluggedIn: plugged,
                minutesToEmpty: minutes)
        }
        return .missing
    }
}
