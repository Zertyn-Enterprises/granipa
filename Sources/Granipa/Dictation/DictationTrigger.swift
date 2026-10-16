import Foundation

enum DictationTrigger {
    /// Holds shorter than this become a toggle (press to start, press again to stop).
    static let toggleThreshold: TimeInterval = 0.22
    /// A release before this with nothing recognized yet is a slow tap, not a
    /// hold: Right ⌘ taps measured 0.40–0.60 s, and a Bluetooth mic may not be
    /// running yet, so stopping would only report "Didn't catch that".
    static let silentTapThreshold: TimeInterval = 1.5

    enum ReleaseAction: Equatable {
        case keepAsToggle
        case stop
    }

    static func actionOnRelease(held: TimeInterval, heardSpeech: Bool) -> ReleaseAction {
        if held < toggleThreshold { return .keepAsToggle }
        if !heardSpeech, held < silentTapThreshold { return .keepAsToggle }
        return .stop
    }

    /// `press`/`release` are hardware event times (seconds since system startup),
    /// not `Date.now` after a MainActor hop.
    static func actionOnRelease(
        press: TimeInterval, release: TimeInterval, heardSpeech: Bool
    ) -> ReleaseAction {
        actionOnRelease(held: max(0, release - press), heardSpeech: heardSpeech)
    }
}

enum DictationEngineID: String, CaseIterable, Sendable {
    case local
    case muse
}

enum DictationPhase: Equatable, Sendable {
    case idle
    case preparing
    case listening
    case processing
    case done
    case failed(String)

    var isActive: Bool {
        switch self {
        case .preparing, .listening, .processing: true
        default: false
        }
    }
}
