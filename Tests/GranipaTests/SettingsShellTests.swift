import CoreGraphics
import Testing

@testable import Granipa

@Suite struct SettingsShellTests {
    @Test func sidebarSectionsMatchTheShellContract() {
        #expect(SettingsSection.allCases.map(\.title) == [
            "General", "Dictation", "Shortcuts", "Permissions", "AI", "Extras", "Integrations",
        ])
        #expect(SettingsSection.allCases.map(\.icon) == [
            "gearshape", "mic", "keyboard", "lock.shield", "wand.and.stars", "puzzlepiece",
            "network",
        ])
    }

    @Test func generalRemainsTheInitialSelection() {
        #expect(SettingsSection.initialSelection == .general)
        #expect(SettingsSection.allCases.first == SettingsSection.initialSelection)
    }

    @Test func selectionRoundTripsThroughRawValues() {
        for section in SettingsSection.allCases {
            #expect(SettingsSection(rawValue: section.rawValue) == section)
        }
        #expect(SettingsSection(rawValue: "billing") == nil)
        #expect(SettingsSection(rawValue: "account") == nil)
    }

    @Test func compositeSectionsKeepTheirSubPages() {
        #expect(SettingsSection.ai.subPages == [.providers, .templates])
        #expect(SettingsSection.extras.subPages == [.clipboardAndOCR, .windows, .battery])
        #expect(SettingsSection.integrations.subPages == [.api, .webhooks])
        #expect(SettingsSection.general.subPages.isEmpty)
        #expect(SettingsSection.dictation.subPages.isEmpty)
        #expect(SettingsSection.shortcuts.subPages.isEmpty)
        #expect(SettingsSection.permissions.subPages.isEmpty)
    }

    @Test func subPageTitlesMatchTheOriginalTabs() {
        #expect(SettingsSubPage.providers.title == "Providers")
        #expect(SettingsSubPage.templates.title == "Templates")
        #expect(SettingsSubPage.clipboardAndOCR.title == "Clipboard & OCR")
        #expect(SettingsSubPage.windows.title == "Windows")
        #expect(SettingsSubPage.battery.title == "Battery")
        #expect(SettingsSubPage.api.title == "API")
        #expect(SettingsSubPage.webhooks.title == "Webhooks")
    }

    @Test func windowStaysResponsiveWithoutClipping() {
        #expect(SettingsLayout.minWindowWidth == 900)
        #expect(SettingsLayout.idealWindowWidth == 1100)
        #expect(SettingsLayout.minWindowHeight == 680)
        #expect(SettingsLayout.minWindowWidth < SettingsLayout.idealWindowWidth)
        #expect(
            SettingsLayout.contentMaxWidth
                <= SettingsLayout.idealWindowWidth - SettingsLayout.sidebarWidth)
    }
}
