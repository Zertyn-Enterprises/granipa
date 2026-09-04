import CoreGraphics
import Foundation

enum WindowInventory {
    static func occupiedFrames(on screen: CGRect, ignoring current: CGRect) -> [CGRect] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard
            let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]
        else { return [] }
        var result: [CGRect] = []
        for info in list {
            let layer = info[kCGWindowLayer as String] as? Int ?? 0
            guard layer == 0 else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: CGFloat] else {
                continue
            }
            let rect = CGRect(
                x: bounds["X"] ?? 0,
                y: bounds["Y"] ?? 0,
                width: bounds["Width"] ?? 0,
                height: bounds["Height"] ?? 0)
            guard !WindowLayout.isSame(rect, current) else { continue }
            guard rect.intersects(screen) else { continue }
            guard rect.width >= WindowLayout.minGap, rect.height >= WindowLayout.minGap else {
                continue
            }
            result.append(rect)
        }
        return result
    }
}
