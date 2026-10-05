import CoreGraphics
import Testing

@testable import Granipa

@Suite struct WindowLayoutTests {
    // Visible frame with a menu-bar offset, AX coords (top-left origin).
    private let screen = CGRect(x: 0, y: 25, width: 1600, height: 975)

    @Test func halvesTileWithoutGapsOrOverlap() {
        let left = WindowLayout.frame(for: .leftHalf, screen: screen, current: .zero)!
        let right = WindowLayout.frame(for: .rightHalf, screen: screen, current: .zero)!
        #expect(left.minX == screen.minX)
        #expect(left.maxX == right.minX)
        #expect(right.maxX == screen.maxX)
        #expect(left.height == screen.height)
        #expect(left.minY == screen.minY)
    }

    @Test func quartersCoverScreen() {
        let topLeft = WindowLayout.frame(for: .topLeft, screen: screen, current: .zero)!
        let bottomRight = WindowLayout.frame(for: .bottomRight, screen: screen, current: .zero)!
        #expect(topLeft.origin == screen.origin)
        #expect(bottomRight.maxX == screen.maxX)
        #expect(bottomRight.maxY == screen.maxY)
        #expect(topLeft.maxY == bottomRight.minY)
    }

    @Test func thirdsSpanFullWidth() {
        let first = WindowLayout.frame(for: .firstThird, screen: screen, current: .zero)!
        let middle = WindowLayout.frame(for: .centerThird, screen: screen, current: .zero)!
        let last = WindowLayout.frame(for: .lastThird, screen: screen, current: .zero)!
        #expect(first.minX == screen.minX)
        #expect(first.maxX == middle.minX)
        #expect(middle.maxX == last.minX)
        #expect(last.maxX == screen.maxX)
    }

    @Test func maximizeFillsVisibleFrame() {
        #expect(WindowLayout.frame(for: .maximize, screen: screen, current: .zero) == screen)
    }

    @Test func centerKeepsSizeAndClampsToScreen() {
        let current = CGRect(x: 10, y: 100, width: 800, height: 500)
        let centered = WindowLayout.frame(for: .center, screen: screen, current: current)!
        #expect(centered.width == 800)
        #expect(centered.height == 500)
        #expect(abs(centered.midX - screen.midX) <= 1)
        #expect(abs(centered.midY - screen.midY) <= 1)

        let huge = CGRect(x: 0, y: 0, width: 4000, height: 3000)
        let clamped = WindowLayout.frame(for: .center, screen: screen, current: huge)!
        #expect(clamped.width == screen.width)
        #expect(clamped.height == screen.height)
    }

    @Test func restoreHasNoComputedFrame() {
        #expect(WindowLayout.frame(for: .restore, screen: screen, current: .zero) == nil)
    }

    @Test func leftSnapFillsRemainderWhenLeftIsOccupied() {
        let parked = CGRect(x: 0, y: 25, width: 400, height: 975)
        let moving = CGRect(x: 800, y: 25, width: 800, height: 975)
        let frame = WindowLayout.frame(
            for: .leftHalf, screen: screen, current: moving, occupied: [parked])!
        #expect(frame.minX == 400)
        #expect(frame.maxX == screen.maxX)
        #expect(frame.height == screen.height)
    }

    @Test func leftSnapIgnoresTheMovingWindowItself() {
        let current = CGRect(x: 0, y: 25, width: 400, height: 975)
        let frame = WindowLayout.frame(
            for: .leftHalf, screen: screen, current: current, occupied: [current])!
        #expect(frame.minX == screen.minX)
        #expect(frame.width == (screen.width / 2).rounded())
    }

    @Test func leftSnapIgnoresAlmostMaximizedWindows() {
        let huge = CGRect(x: 0, y: 25, width: 1500, height: 975)
        let moving = CGRect(x: 200, y: 100, width: 300, height: 300)
        let frame = WindowLayout.frame(
            for: .leftHalf, screen: screen, current: moving, occupied: [huge])!
        #expect(frame.minX == screen.minX)
        #expect(frame.width == (screen.width / 2).rounded())
    }

    @Test func rightSnapFillsRemainderWhenRightIsOccupied() {
        let parked = CGRect(x: 1000, y: 25, width: 600, height: 975)
        let moving = CGRect(x: 0, y: 25, width: 800, height: 975)
        let frame = WindowLayout.frame(
            for: .rightHalf, screen: screen, current: moving, occupied: [parked])!
        #expect(frame.minX == screen.minX)
        #expect(frame.maxX == 1000)
        #expect(frame.height == screen.height)
    }

    @Test func gridShapeFollowsWindowCount() {
        let shapes = [1, 2, 3, 4, 5, 6, 7, 8, 9].map {
            WindowLayout.gridShape(count: $0, screen: screen)
        }
        #expect(shapes.map(\.columns) == [1, 2, 3, 2, 3, 3, 4, 4, 3])
        #expect(shapes.map(\.rows) == [1, 1, 1, 2, 2, 2, 2, 2, 3])

        let portrait = CGRect(x: 0, y: 25, width: 1080, height: 1895)
        let six = WindowLayout.gridShape(count: 6, screen: portrait)
        #expect(six.columns == 2)
        #expect(six.rows == 3)
    }

    @Test func gridFramesCoverScreenWithoutOverlap() {
        for count in 1...12 {
            let frames = WindowLayout.gridFrames(count: count, screen: screen)
            #expect(frames.count == count)
            let area = frames.reduce(CGFloat(0)) { $0 + $1.width * $1.height }
            #expect(area == screen.width * screen.height)
            for (i, a) in frames.enumerated() {
                #expect(screen.contains(a))
                for b in frames[(i + 1)...] {
                    let overlap = a.intersection(b)
                    #expect(overlap.width * overlap.height == 0)
                }
            }
        }
    }

    @Test func shortLastRowStretchesToFullWidth() {
        let five = WindowLayout.gridFrames(count: 5, screen: screen)
        let bottom = five.suffix(2)
        #expect(bottom.allSatisfy { $0.width == screen.width / 2 })
        #expect(bottom.first?.minX == screen.minX)
        #expect(bottom.last?.maxX == screen.maxX)
    }

    @Test func retilingKeepsEachWindowInItsCell() {
        let grid = WindowLayout.gridFrames(count: 6, screen: screen)
        let shuffled = [grid[4], grid[0], grid[5], grid[2], grid[1], grid[3]]
        let order = WindowLayout.tileOrder(shuffled)
        #expect(order.map { shuffled[$0] } == grid)
    }

    @Test func stageStripReservesItsEdge() {
        let left = WindowLayout.usableFrame(screen: screen, stageStrip: .left)
        #expect(left.minX == screen.minX + WindowLayout.stageStripWidth)
        #expect(left.maxX == screen.maxX)
        #expect(left.height == screen.height)

        let right = WindowLayout.usableFrame(screen: screen, stageStrip: .right)
        #expect(right.minX == screen.minX)
        #expect(right.maxX == screen.maxX - WindowLayout.stageStripWidth)

        #expect(WindowLayout.usableFrame(screen: screen, stageStrip: nil) == screen)
    }

    @Test func tileHasNoSingleWindowFrame() {
        #expect(WindowLayout.frame(for: .tileAppWindows, screen: screen, current: .zero) == nil)
    }
}
