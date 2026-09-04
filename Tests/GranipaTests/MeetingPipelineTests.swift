import Testing

@testable import Granipa

@Suite struct MeetingPipelineTests {
    @Test func recordingWhileTranscriptionHealthy() {
        #expect(
            MeetingPipeline.phase(
                status: .recording, isRecording: true,
                transcriptionPhase: .live, isEnhancing: false)
            == .recording)
        #expect(
            MeetingPipeline.phase(
                status: .recording, isRecording: true,
                transcriptionPhase: .preparing, isEnhancing: false)
            == .recording)
    }

    @Test func liveFailureWhileStillCapturingIsRetryableFailed() {
        #expect(
            MeetingPipeline.phase(
                status: .recording, isRecording: true,
                transcriptionPhase: .failed("model missing"), isEnhancing: false)
            == .failed("model missing"))
    }

    @Test func stoppedMeetingWalksThePostPipeline() {
        // Drain: stopped, coordinator still attached — even if its phase sat
        // at .failed, the drain itself is the finishing stage.
        #expect(
            MeetingPipeline.phase(
                status: .processing, isRecording: false,
                transcriptionPhase: .finishing, isEnhancing: false)
            == .finishing)
        #expect(
            MeetingPipeline.phase(
                status: .processing, isRecording: false,
                transcriptionPhase: .failed("model missing"), isEnhancing: false)
            == .finishing)
        // Coordinator done: diarization stage before the LLM pass.
        #expect(
            MeetingPipeline.phase(
                status: .processing, isRecording: false,
                transcriptionPhase: nil, isEnhancing: false)
            == .transcribing)
        // LLM pass.
        #expect(
            MeetingPipeline.phase(
                status: .processing, isRecording: false,
                transcriptionPhase: nil, isEnhancing: true)
            == .enhancing)
        #expect(
            MeetingPipeline.phase(
                status: .ready, isRecording: false,
                transcriptionPhase: nil, isEnhancing: false)
            == .ready)
    }

    @Test func reEnhancementOfAReadyMeetingShowsEnhancing() {
        // The API trigger (and any manual re-run) enhances finished meetings:
        // the row must not sit on "ready" while the LLM writes notes.
        #expect(
            MeetingPipeline.phase(
                status: .ready, isRecording: false,
                transcriptionPhase: nil, isEnhancing: true)
            == .enhancing)
    }

    @Test func idleForUntouchedAndOrphanRows() {
        #expect(
            MeetingPipeline.phase(
                status: nil, isRecording: false,
                transcriptionPhase: nil, isEnhancing: false)
            == .idle)
        #expect(
            MeetingPipeline.phase(
                status: .recording, isRecording: false,
                transcriptionPhase: nil, isEnhancing: false)
            == .idle)
    }
}

@Suite struct DictationRetryContractTests {
    @Test func transientCausesAreRetryable() {
        #expect(DictationError.empty.isRetryable)
        #expect(DictationError.micBusy.isRetryable)
        #expect(DictationError.audioFormat.isRetryable)
        #expect(DictationError.museConnect.isRetryable)
    }

    @Test func deterministicCausesAreNot() {
        #expect(!DictationError.museFailed("bad key").isRetryable)
        #expect(!DictationError.cancelled.isRetryable)
    }
}
