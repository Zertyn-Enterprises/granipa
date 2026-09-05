import Testing

@testable import Granipa

/// The idle Readiness card may show the Apple-locale Language row only when
/// the configured engine is local — the same rule the live Session card
/// applies to `dictation.engineID`.
@Suite struct DictationIdleEngineTests {
    @Test func absentLocalAndUnknownConfigurationsResolveToLocal() {
        #expect(DictationIdleEngine(configuredRaw: nil) == .local)
        #expect(DictationIdleEngine(configuredRaw: "local") == .local)
        #expect(DictationIdleEngine(configuredRaw: "bogus") == .local)
    }

    @Test func configuredMuseSuppressesTheAppleLocaleRow() {
        #expect(DictationIdleEngine(configuredRaw: "muse") == .muse)
    }
}
