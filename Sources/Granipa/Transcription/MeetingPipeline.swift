import Foundation

/// The one state Home rows, the HUD, and the menu bar can paint without
/// reconstructing it from recorder flags, coordinator phase, and the enhance
/// set. Derived purely from values the views already hold.
enum MeetingPipelinePhase: Equatable, Sendable {
    case idle
    case recording
    /// Stopped; the transcriber is still draining its last results.
    case finishing
    /// Post-stop processing before the LLM pass (diarization, speaker names).
    case transcribing
    case enhancing
    case ready
    /// Live transcription failed while capture continues — retryable.
    case failed(String)
}

enum MeetingPipeline {
    static func phase(
        status: MeetingStatus?,
        isRecording: Bool,
        transcriptionPhase: TranscriptionCoordinator.Phase?,
        isEnhancing: Bool
    ) -> MeetingPipelinePhase {
        if isRecording {
            if case .failed(let message) = transcriptionPhase {
                return .failed(message)
            }
            return .recording
        }
        switch status {
        case .processing:
            if transcriptionPhase != nil {
                return .finishing
            }
            return isEnhancing ? .enhancing : .transcribing
        case .ready:
            // Re-enhancement (API trigger, manual re-run) works on finished
            // meetings; the LLM pass outranks the resting status.
            return isEnhancing ? .enhancing : .ready
        case .recording, nil:
            // An orphaned "recording" row (recovered at launch) shows as idle.
            return .idle
        }
    }
}
