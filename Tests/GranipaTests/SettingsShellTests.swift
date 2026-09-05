import AppKit
import CoreGraphics
import SwiftUI
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

    @MainActor
    @Test func tallGroupedFormStaysBoundedAtTheMinimumWindow() {
        let tallForm = Form {
            ForEach(0..<80, id: \.self) { row in
                Toggle("Setting row \(row)", isOn: .constant(true))
            }
        }
        .formStyle(.grouped)
        let page = SettingsPage(title: "Probe", subtitle: "Layout probe with tall content.") {
            tallForm
        }
        let host = NSHostingController(rootView: page)
        // Content area at the 900x680 minimum: 900 - 220 sidebar wide, 680 tall.
        let fitted = host.sizeThatFits(in: CGSize(width: 680, height: 680))
        #expect(fitted.width <= 680)
        #expect(fitted.height <= 680)
    }
}

@Suite struct SettingsDraftsTests {
    @Test func dictationDraftsLoadOnceAndSurviveRemounts() {
        var drafts = DictationKeyDrafts()
        drafts.loadOnce { _ in "keychain-fake" }
        #expect(drafts.museKey == "keychain-fake")
        #expect(drafts.spaceXAIKey == "keychain-fake")
        #expect(drafts.customKey == "keychain-fake")

        drafts.museKey = "typed-muse-not-saved"
        drafts.spaceXAIKey = "typed-spacexai-not-saved"
        drafts.customKey = "typed-custom-not-saved"

        // Remount: DictationSettings reappears and its onAppear runs loadOnce again.
        drafts.loadOnce { _ in "keychain-fake" }

        #expect(drafts.museKey == "typed-muse-not-saved")
        #expect(drafts.spaceXAIKey == "typed-spacexai-not-saved")
        #expect(drafts.customKey == "typed-custom-not-saved")
    }

    @Test func editorDraftsFallBackToPersistedAndSurviveRemounts() {
        var drafts = EditorDrafts<Webhook>()
        let persisted = Webhook.new()
        #expect(drafts[persisted] == persisted)

        var edited = persisted
        edited.url = "https://draft.example/hook"
        edited.enabled.toggle()
        drafts[persisted] = edited

        // The editor is rebuilt after a section/subpage switch; it must see the draft.
        #expect(drafts[persisted] == edited)
        #expect(drafts[persisted].url == "https://draft.example/hook")
        #expect(drafts[persisted].id == persisted.id)
        #expect(drafts[persisted].secret == persisted.secret)

        var templateDrafts = EditorDrafts<MeetingTemplate>()
        let builtin = MeetingTemplate.builtins[0]
        var editedTemplate = builtin
        editedTemplate.prompt = "typed prompt not saved"
        templateDrafts[builtin] = editedTemplate
        #expect(templateDrafts[builtin].prompt == "typed prompt not saved")
        #expect(templateDrafts[builtin].name == builtin.name)
    }
}
