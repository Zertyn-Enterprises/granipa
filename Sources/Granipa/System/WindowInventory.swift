import CoreGraphics
import Foundation

enum WindowInventory {
    static func occupiedFrames(on screen: CGRect, ignoring current: CGRect) -> [CGRect] {
        onscreenFrames().filter {
            !WindowLayout.isSame($0, current)
                && $0.intersects(screen)
                && $0.width >= WindowLayout.minGap
                && $0.height >= WindowLayout.minGap
        }
    }

    /// Normal-layer windows currently drawn on screen. Stage Manager draws the
    /// windows parked in its strip scaled down, so their bounds differ from the
    /// frame Accessibility reports for them.
    static func onscreenFrames(pid: pid_t? = nil) -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        var result: [CGRect] = []
        for info in list {
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            if let pid, info[kCGWindowOwnerPID as String] as? pid_t != pid { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            result.append(
                CGRect(
                    x: bounds["X"] ?? 0,
                    y: bounds["Y"] ?? 0,
                    width: bounds["Width"] ?? 0,
                    height: bounds["Height"] ?? 0))
        }
        return result
    }

    /// Edge holding the Stage Manager strip, or nil when Stage Manager is off or
    /// its strip is set to auto-hide. The strip sits opposite a side-docked Dock.
    static var stageStripSide: WindowLayout.StripSide? {
        let windowManager = UserDefaults(suiteName: "com.apple.WindowManager")
        guard windowManager?.bool(forKey: "GloballyEnabled") == true,
            windowManager?.bool(forKey: "AutoHide") != true
        else { return nil }
        switch UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") {
        case "left": return .right
        case "right": return .left
        default:
            return Locale.current.language.characterDirection == .rightToLeft ? .right : .left
        }
    }
}
