import Testing

@testable import Granipa

@Suite struct PermissionLanguagesTests {
    @Test func unknownProbeIsCheckingNotAbsent() {
        #expect(
            LanguageChipStatus.resolve(knownInstalled: nil, localeID: "en-US") == .checking)
        #expect(
            LanguageChipStatus.resolve(knownInstalled: nil, localeID: "en-US").label
                == "Checking")
        #expect(
            LanguageChipStatus.resolve(knownInstalled: nil, localeID: "en-US").accessibilityStatus
                == "checking")
        #expect(LanguageChipStatus.checking.label != "Not installed")
        #expect(LanguageChipStatus.checking.label != LanguageChipStatus.absent.label)
    }

    @Test func knownEmptySetIsAbsentAndKnownIDIsInstalled() {
        #expect(
            LanguageChipStatus.resolve(knownInstalled: [], localeID: "en-US") == .absent)
        #expect(
            LanguageChipStatus.resolve(knownInstalled: [], localeID: "en-US").label
                == "Not installed")
        #expect(
            LanguageChipStatus.resolve(knownInstalled: ["en-US", "es-ES"], localeID: "en-US")
                == .installed)
        #expect(
            LanguageChipStatus.resolve(knownInstalled: ["en-US"], localeID: "es-ES") == .absent)
        #expect(LanguageChipStatus.installed.label == "Installed")
    }

    @Test func localeChangeClearsLastKnownAndActivationDoesNot() {
        #expect(
            LanguageInstallProbe.shouldClearKnown(
                checkedLocales: ["en-US", "es-ES"],
                visibleLocales: ["en-US", "fr-FR"]))
        #expect(
            !LanguageInstallProbe.shouldClearKnown(
                checkedLocales: ["en-US", "es-ES"],
                visibleLocales: ["en-US", "es-ES"]))
        #expect(
            LanguageInstallProbe.shouldClearKnown(
                checkedLocales: [],
                visibleLocales: ["en-US"]))
    }

    @Test func completedProbeForADifferentLocaleListIsStale() {
        #expect(
            LanguageInstallProbe.isStale(
                requested: ["en-US", "es-ES"],
                visible: ["en-US", "fr-FR"]))
        #expect(
            !LanguageInstallProbe.isStale(
                requested: ["en-US", "es-ES"],
                visible: ["en-US", "es-ES"]))
    }

    @Test func taskIDChangesWithLocalesAndActivationTick() {
        let locales = ["en-US", "es-ES"]
        let first = LanguageInstallProbe.taskID(localeIDs: locales, refreshTick: 0)
        let activation = LanguageInstallProbe.taskID(localeIDs: locales, refreshTick: 1)
        let localeChange = LanguageInstallProbe.taskID(localeIDs: ["en-US"], refreshTick: 0)
        #expect(first != activation)
        #expect(first != localeChange)
        #expect(activation != localeChange)
        #expect(first.contains("en-US,es-ES"))
    }
}
