import Testing

@testable import Granipa

/// Contract: Muse touches meeting system audio only when the user picked the
/// engine AND a key exists. Everything else — unset, empty, local, keyless —
/// stays on the Apple engine.
@Suite struct MeetingASRPolicyTests {
    @Test func museRequiresExplicitEngineAndKey() {
        #expect(MeetingASRPolicy.usesMuseForSystem(engine: "muse", hasMuseKey: true))
    }

    @Test func everythingElseStaysLocal() {
        #expect(!MeetingASRPolicy.usesMuseForSystem(engine: nil, hasMuseKey: true))
        #expect(!MeetingASRPolicy.usesMuseForSystem(engine: "", hasMuseKey: true))
        #expect(!MeetingASRPolicy.usesMuseForSystem(engine: "muse", hasMuseKey: false))
        #expect(!MeetingASRPolicy.usesMuseForSystem(engine: "local", hasMuseKey: true))
    }

    @Test func liveASRIsOffUnlessExplicitlyEnabled() {
        #expect(!MeetingASRPolicy.usesLiveASR(flag: nil))
        #expect(!MeetingASRPolicy.usesLiveASR(flag: false))
        #expect(MeetingASRPolicy.usesLiveASR(flag: true))
    }
}
