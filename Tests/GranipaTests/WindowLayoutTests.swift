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
}
