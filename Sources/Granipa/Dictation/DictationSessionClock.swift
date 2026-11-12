import Foundation
import Observation

/// Tracks when the current dictation session started so the inspector can show
/// an honest elapsed timer. Owns no capture: it only observes
/// `DictationController.phase` changes. Armed from `DictationOverlayController.attach`,
/// which AppState calls at startup and `DictationController.start` on every session.
@MainActor
@Observable
final class DictationSessionClock {
    static let shared = DictationSessionClock()

    private(set) var sessionStartedAt: Date?
    private var isObserving = false
    private let controller: DictationController

    init(controller: DictationController = .shared) {
        self.controller = controller
    }

    func beginObserving() {
        guard !isObserving else { return }
        isObserving = true
        observe()
    }

    private func observe() {
        withObservationTracking { _ = controller.phase } onChange: { [weak self] in
            // onChange fires before the new value is stored; read it on the
            // next main-actor turn, where `observe()` also re-arms tracking.
            Task { @MainActor [weak self] in self?.observe() }
        }
        track(controller.phase)
    }

    /// A session begins when the phase enters `.preparing` (fresh press or retry);
    /// `.listening`/`.processing` continue it; terminal phases freeze the value.
    func track(_ phase: DictationPhase, now: Date = .now) {
        if phase == .preparing {
            sessionStartedAt = now
        }
    }

    /// `HH:MM:SS` elapsed for a running session; nil when the start is unknown.
    static func elapsedLabel(startedAt: Date?, now: Date = .now) -> String? {
        guard let startedAt else { return nil }
        let seconds = max(0, Int(now.timeIntervalSince(startedAt).rounded(.down)))
        return String(
            format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}
