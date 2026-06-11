import CoreGraphics

enum WindowAction: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird
    case maximize, center, restore
}

// All math in top-left-origin (AX) coordinates: y grows downward.
enum WindowLayout {
    static func frame(for action: WindowAction, screen s: CGRect, current: CGRect) -> CGRect? {
        let halfW = (s.width / 2).rounded()
        let halfH = (s.height / 2).rounded()
        let thirdW = (s.width / 3).rounded()
        switch action {
        case .leftHalf:
            return CGRect(x: s.minX, y: s.minY, width: halfW, height: s.height)
        case .rightHalf:
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
}
