import Testing

@testable import Granipa

@Suite struct OnboardingDefaultsTests {
    @Test(arguments: [
        (installed: ["codex", "gemini"], chosen: nil as String?, expected: "codex" as String?),
        (installed: ["codex"], chosen: "claude", expected: nil),
        (installed: [], chosen: nil, expected: nil),
    ])
    func preselectsTheFirstInstalledProviderOnlyWhenNoneWasChosen(
        installed: [String], chosen: String?, expected: String?
    ) {
        #expect(OnboardingDefaults.provider(installedIDs: installed, chosen: chosen) == expected)
    }
}
