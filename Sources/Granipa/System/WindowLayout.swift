import CoreGraphics

enum WindowAction: String, CaseIterable, Sendable {
    case leftHalf, rightHalf, topHalf, bottomHalf
    case topLeft, topRight, bottomLeft, bottomRight
    case firstThird, centerThird, lastThird
    case maximize, center, restore
    case tileAppWindows

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
        case .tileAppWindows: "Tile app windows"
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
        case .restore, .tileAppWindows:
            return nil
        }
    }

    enum StripSide: Sendable { case left, right }

    /// Stage Manager keeps its strip of other app groups on one edge; snaps must
    /// not cover it. Strip windows wider than the default reservation widen it.
    static let stageStripWidth: CGFloat = 150
    static let stageStripGap: CGFloat = 12

    static func usableFrame(
        screen s: CGRect, stageStrip side: StripSide?, stripWindows: [CGRect] = []
    ) -> CGRect {
        guard let side else { return s }
        let band = max(s.width * 0.15, stageStripWidth)
        var inset = stageStripWidth
        for w in stripWindows where w.intersects(s) && w.width < band {
            switch side {
            case .left where w.minX < s.minX + band:
                inset = max(inset, w.maxX - s.minX + stageStripGap)
            case .right where w.maxX > s.maxX - band:
                inset = max(inset, s.maxX - w.minX + stageStripGap)
            default:
                continue
            }
        }
        inset = min(inset, band)
        switch side {
        case .left:
            return CGRect(x: s.minX + inset, y: s.minY, width: s.width - inset, height: s.height)
        case .right:
            return CGRect(x: s.minX, y: s.minY, width: s.width - inset, height: s.height)
        }
    }

    /// Up to three windows share one row; beyond that rows grow as √(n/2), so a
    /// landscape screen gets 4→2×2, 6→3×2, 8→4×2, 9→3×3. Portrait swaps the axes.
    static func gridShape(count: Int, screen s: CGRect) -> (columns: Int, rows: Int) {
        guard count > 0 else { return (0, 0) }
        let rows = count <= 3 ? 1 : Int((Double(count) / 2).squareRoot().rounded(.up))
        let columns = Int((Double(count) / Double(rows)).rounded(.up))
        return s.height > s.width ? (rows, columns) : (columns, rows)
    }

    /// Row-major cells; a short last row stretches its windows to the full width.
    static func gridFrames(count: Int, screen s: CGRect) -> [CGRect] {
        let columns = gridShape(count: count, screen: s).columns
        guard columns > 0 else { return [] }
        let rows = (count + columns - 1) / columns
        var frames: [CGRect] = []
        for row in 0..<rows {
            let inRow = min(columns, count - row * columns)
            let top = s.minY + (s.height * CGFloat(row) / CGFloat(rows)).rounded()
            let bottom = s.minY + (s.height * CGFloat(row + 1) / CGFloat(rows)).rounded()
            for column in 0..<inRow {
                let left = s.minX + (s.width * CGFloat(column) / CGFloat(inRow)).rounded()
                let right = s.minX + (s.width * CGFloat(column + 1) / CGFloat(inRow)).rounded()
                frames.append(CGRect(x: left, y: top, width: right - left, height: bottom - top))
            }
        }
        return frames
    }

    /// Reading order (top row first, then left to right) so re-tiling an
    /// already tiled set keeps every window in its cell.
    static func tileOrder(_ frames: [CGRect]) -> [Int] {
        frames.indices.sorted {
            (frames[$0].minY.rounded(), frames[$0].minX, $0)
                < (frames[$1].minY.rounded(), frames[$1].minX, $1)
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
