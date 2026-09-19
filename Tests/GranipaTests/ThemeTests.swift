import SwiftUI
import Testing

@testable import Granipa

@Suite struct ThemeTests {
    @Test @MainActor func motionDurationsMatchTheContract() {
        #expect(Theme.motionFast == 0.08)
        #expect(Theme.motionNormal == 0.15)
        #expect(PanelMotion.showDuration == 0.34)
        #expect(PanelMotion.hideDuration == 0.20)
        #expect(PanelMotion.rise == 40)
    }

    @Test func scaleTokensMatchTheContract() {
        #expect(Theme.spaceM == 12)
        #expect(Theme.spaceL == 16)
        #expect(Theme.spaceXL == 24)
        #expect(Theme.radiusS == 8)
        #expect(Theme.radiusM == 12)
        #expect(Theme.radiusL == 16)
        #expect(Theme.radiusOverlay == 24)
        #expect(DictationController.waveformBars == 40)
    }

    @Test func darkTokensMatchTheV2Contract() {
        #expect(Theme.bgHex == 0x141617)
        #expect(Theme.bgSidebarHex == 0x17191A)
        #expect(Theme.cardHex == 0x1E2123)
        #expect(Theme.accentHex == 0xF05423)
        #expect(Theme.accentGlowOpacity == 0.4)
        #expect(Theme.titleSize == 32)
        #expect(Theme.sectionSize == 16)
    }

    @Test func sparklineIsStableAndBounded() {
        let a = MeetingSparkline.samples(id: "abc")
        let b = MeetingSparkline.samples(id: "abc")
        #expect(a == b)
        #expect(a.count == 52)
        #expect(a.allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(MeetingSparkline.samples(id: "xyz") != a)
    }
}
