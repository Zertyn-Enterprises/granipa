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

    init() {}

    func beginObserving() {
        guard !isObserving else { return }
        isObserving = true
        observe()
    }

    private func observe() {
        let controller = DictationController.shared
        withObservationTracking { _ = controller.phase } onChange: {
            // Phase is only ever mutated on the main actor, so the change
            // notification arrives there too; re-arm without a task hop.
            MainActor.assumeIsolated {
                DictationSessionClock.shared.phaseDidChange()
            }
        }
        track(controller.phase)
    }

    private func phaseDidChange() {
        track(DictationController.shared.phase)
        observe()
    }

    /// A session begins when the phase enters `.preparing` (fresh press or retry);
    /// `.listening`/`.processing` continue it; terminal phases freeze the value.
    func track(_ phase: DictationPhase) {
        if phase == .preparing {
            sessionStartedAt = .now
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
