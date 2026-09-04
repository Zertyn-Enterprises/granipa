import SwiftUI
import Testing

@testable import Granipa

@Suite struct ThemeTests {
    @Test func motionDurationsMatchTheContract() {
        #expect(Theme.motionFast == 0.08)
        #expect(Theme.motionNormal == 0.15)
        #expect(PanelMotion.showDuration == 0.34)
        #expect(PanelMotion.hideDuration == 0.20)
        #expect(PanelMotion.rise == 40)
    }

    @Test func scaleTokensMatchTheContract() {
        #expect(Theme.spaceXS == 4)
        #expect(Theme.spaceS == 8)
        #expect(Theme.spaceM == 12)
        #expect(Theme.spaceL == 16)
        #expect(Theme.spaceXL == 24)
        #expect(Theme.radiusS == 8)
        #expect(Theme.radiusM == 12)
        #expect(Theme.radiusL == 16)
        #expect(Theme.radiusOverlay == 24)
        _ = Theme.fontSmall
        _ = Theme.fontCaption
        _ = Theme.fontBody
        _ = Theme.spring
        #expect(DictationController.waveformBars == 40)
    }

    @Test func colorTokensExist() {
        _ = Theme.channelMe
        _ = Theme.fillSubtle
        _ = Theme.fillHover
        _ = Theme.strokeStrong
        _ = Theme.statusListening
        _ = Theme.statusProcessing
        _ = Theme.statusDone
        _ = Theme.statusLoading
        _ = Theme.statusFailed
        _ = Theme.brandGradient
        _ = Theme.brandPurple
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
