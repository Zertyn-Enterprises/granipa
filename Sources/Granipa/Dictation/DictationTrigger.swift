import Foundation

enum DictationTrigger {
    /// Holds shorter than this become a toggle (press to start, press again to stop).
    static let toggleThreshold: TimeInterval = 0.22

    enum ReleaseAction: Equatable {
        case keepAsToggle
        case stop
    }

    static func actionOnRelease(held: TimeInterval) -> ReleaseAction {
        held < toggleThreshold ? .keepAsToggle : .stop
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
