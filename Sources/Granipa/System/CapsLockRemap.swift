import Carbon.HIToolbox
import Foundation
import IOKit.hidsystem
import os

/// Caps Lock only toggles state; apps never see it released. To make it a
/// hold-to-use macro key it is remapped to F18 at the HID layer while it is the
/// macro (Apple TN2450, the Hyperkey/Raycast approach). Other mappings stay.
enum CapsLockRemap {
    static let capsLockUsage: UInt64 = 0x7_0000_0039
    static let f18Usage: UInt64 = 0x7_0000_006D
    static let f18KeyCode = UInt32(kVK_F18)

    private static let srcKey = "HIDKeyboardModifierMappingSrc"
    private static let dstKey = "HIDKeyboardModifierMappingDst"
    /// Set only when Grañipa installed the mapping, so one placed by another
    /// tool (Raycast, hidutil) is never removed. A crash leaves it installed
    /// until the next launch reconciles it.
    private static let ownedKey = "capsLockRemapOwned"
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "hyper")

    static func merged(_ existing: [[String: UInt64]], enabled: Bool) -> [[String: UInt64]] {
        var mappings = existing.filter {
            !($0[srcKey] == capsLockUsage && $0[dstKey] == f18Usage)
        }
        if enabled {
            mappings.append([srcKey: capsLockUsage, dstKey: f18Usage])
        }
        return mappings
    }

    enum Change: Equatable {
        case none, install, remove
    }

    static func change(present: Bool, owned: Bool, enabled: Bool) -> Change {
        if enabled { return present ? .none : .install }
        return present && owned ? .remove : .none
    }

    static func apply(enabled: Bool) {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let key = kIOHIDUserKeyUsageMapKey as CFString
        let current =
            (IOHIDEventSystemClientCopyProperty(client, key) as? [[String: NSNumber]] ?? [])
            .map { $0.mapValues(\.uint64Value) }
        let present = merged(current, enabled: false) != current
        let owned = UserDefaults.standard.bool(forKey: ownedKey)
        switch change(present: present, owned: owned, enabled: enabled) {
        case .none:
            if !enabled, !present { UserDefaults.standard.removeObject(forKey: ownedKey) }
            return
        case .install:
            let ok = IOHIDEventSystemClientSetProperty(
                client, key, merged(current, enabled: true) as CFArray)
            if ok { UserDefaults.standard.set(true, forKey: ownedKey) }
            log.info("caps lock → F18 remap installed ok=\(ok)")
        case .remove:
            let ok = IOHIDEventSystemClientSetProperty(
                client, key, merged(current, enabled: false) as CFArray)
            if ok { UserDefaults.standard.removeObject(forKey: ownedKey) }
            log.info("caps lock → F18 remap removed ok=\(ok)")
        }
    }
}
