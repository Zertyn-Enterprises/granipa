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

    static func apply(enabled: Bool) {
        let client = IOHIDEventSystemClientCreateSimpleClient(kCFAllocatorDefault)
        let key = kIOHIDUserKeyUsageMapKey as CFString
        let current =
            (IOHIDEventSystemClientCopyProperty(client, key) as? [[String: NSNumber]] ?? [])
            .map { $0.mapValues(\.uint64Value) }
        let next = merged(current, enabled: enabled)
        guard next != current else { return }
        let ok = IOHIDEventSystemClientSetProperty(client, key, next as CFArray)
        log.info("caps lock → F18 remap enabled=\(enabled) ok=\(ok)")
    }
}
