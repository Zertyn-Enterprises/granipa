import CoreGraphics

enum WindowAction: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird
    case maximize, center, restore

    var title: String {
        switch self {
        case .leftHalf: "Left half"
        case .rightHalf: "Right half"
        case .topHalf: "Top half"
        case .bottomHalf: "Bottom half"
        case .topLeft: "Top left"
        case .topRight: "Top right"
        case .bottomLeft: "Bottom left"
        case .bottomRight: "Bottom right"
        case .firstThird: "First third"
        case .centerThird: "Center third"
        case .lastThird: "Last third"
        case .maximize: "Maximize"
        case .center: "Center"
        case .restore: "Restore"
        }
    }

    var hotkeyID: UInt32 {
        UInt32(100 + (Self.allCases.firstIndex(of: self) ?? 0))
    }
}

// All math in top-left-origin (AX) coordinates: y grows downward.
enum WindowLayout {
    static let edgeSlop: CGFloat = 12
    static let minGap: CGFloat = 80

    static func frame(
        for action: WindowAction, screen s: CGRect, current: CGRect, occupied: [CGRect] = []
    ) -> CGRect? {
        let halfW = (s.width / 2).rounded()
        let halfH = (s.height / 2).rounded()
        let thirdW = (s.width / 3).rounded()
        switch action {
        case .leftHalf:
            if let remainder = remainder(afterLeftDockOn: s, occupied: occupied, ignoring: current) {
                return remainder
            }
            return CGRect(x: s.minX, y: s.minY, width: halfW, height: s.height)
        case .rightHalf:
            if let remainder = remainder(afterRightDockOn: s, occupied: occupied, ignoring: current) {
                return remainder
            }
            return CGRect(x: s.minX + halfW, y: s.minY, width: s.width - halfW, height: s.height)
        case .topHalf:
            return CGRect(x: s.minX, y: s.minY, width: s.width, height: halfH)
        case .bottomHalf:
            return CGRect(x: s.minX, y: s.minY + halfH, width: s.width, height: s.height - halfH)
        case .topLeft:
            return CGRect(x: s.minX, y: s.minY, width: halfW, height: halfH)
        case .topRight:
            return CGRect(x: s.minX + halfW, y: s.minY, width: s.width - halfW, height: halfH)
        case .bottomLeft:
            return CGRect(x: s.minX, y: s.minY + halfH, width: halfW, height: s.height - halfH)
        case .bottomRight:
            return CGRect(
                x: s.minX + halfW, y: s.minY + halfH,
                width: s.width - halfW, height: s.height - halfH)
        case .firstThird:
            return CGRect(x: s.minX, y: s.minY, width: thirdW, height: s.height)
        case .centerThird:
            return CGRect(x: s.minX + thirdW, y: s.minY, width: thirdW, height: s.height)
        case .lastThird:
            return CGRect(
                x: s.minX + 2 * thirdW, y: s.minY, width: s.width - 2 * thirdW, height: s.height)
        case .maximize:
            return s
        case .center:
            let width = min(current.width, s.width)
            let height = min(current.height, s.height)
            return CGRect(
                x: s.minX + ((s.width - width) / 2).rounded(),
                y: s.minY + ((s.height - height) / 2).rounded(),
                width: width,
                height: height)
        case .restore:
            return nil
        }
    }

    /// If another window is docked to the left edge, fill everything to its right
    /// instead of covering it. Empty screen → nil (caller uses the classic half).
    static func remainder(
        afterLeftDockOn s: CGRect, occupied: [CGRect], ignoring current: CGRect
    ) -> CGRect? {
        let blockers = occupied.filter {
            !isSame($0, current)
                && abs($0.minX - s.minX) <= edgeSlop
                && $0.height >= s.height * 0.45
                && $0.width >= minGap
                && $0.width <= s.width * 0.85
        }
        guard let edge = blockers.map(\.maxX).max() else { return nil }
        let width = s.maxX - edge
        guard width >= minGap else { return nil }
        return CGRect(x: edge, y: s.minY, width: width, height: s.height)
    }

    static func remainder(
        afterRightDockOn s: CGRect, occupied: [CGRect], ignoring current: CGRect
    ) -> CGRect? {
        let blockers = occupied.filter {
            !isSame($0, current)
                && abs($0.maxX - s.maxX) <= edgeSlop
                && $0.height >= s.height * 0.45
                && $0.width >= minGap
                && $0.width <= s.width * 0.85
        }
        guard let edge = blockers.map(\.minX).min() else { return nil }
        let width = edge - s.minX
        guard width >= minGap else { return nil }
        return CGRect(x: s.minX, y: s.minY, width: width, height: s.height)
    }

    static func isSame(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 4 && abs(a.minY - b.minY) < 4
            && abs(a.width - b.width) < 8 && abs(a.height - b.height) < 8
    }
}
