import Foundation
import Observation

enum SystemTapRetryPolicy {
    static let maxAttempts = 1

    static func shouldRetry(bufferCount: Int, attempts: Int) -> Bool {
        bufferCount == 0 && attempts < maxAttempts
    }
}

@MainActor
@Observable
final class RecordingEngine {
    private(set) var isRecording = false
    private(set) var isStarting = false
    private(set) var meetingID: String?
    private(set) var startedAt: Date?
    private(set) var micLevel: Float = 0
    private(set) var systemLevel: Float = 0
    private(set) var systemAudioWarning: String?
    private(set) var micWarning: String?

    private(set) var session: RecordingSession?
    private let levelGate = LevelGate()
    @ObservationIgnored private var isStopping = false
    @ObservationIgnored private var startingSession: RecordingSession?
    @ObservationIgnored private var channelWatchTask: Task<Void, Never>?

    var isBusy: Bool { isRecording || isStarting }

    func start(meetingID: String) async throws -> RecordingSession {
        guard !isRecording, !isStarting else {
            throw NSError(
                domain: "Granipa", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Already recording another meeting."])
        }
        isStarting = true
        defer { isStarting = false }
        let directory = try AppPaths.audioDirectory(meetingID: meetingID)
        let gate = levelGate
        let session = RecordingSession(
            meetingID: meetingID,
            directory: directory,
            fanOutChunks: MeetingASRPolicy.usesLiveASR()
        ) {
            [weak self] channel, level in
            guard gate.shouldPublish(channel) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch channel {
                case .mic: micLevel = level
                case .system: systemLevel = level
                }
            }
        }
        startingSession = session
        self.meetingID = meetingID
        defer {
            if !isRecording, startingSession === session {
                startingSession = nil
                self.meetingID = nil
            }
        }
        // Voice processing AEC on the input node pegs a core and hangs Record
        // (pid 25501: 134% CPU, 8 hangs) even with live ASR off. Capture without it.
        await Task.yield()
        try Task.checkCancellation()
        try session.startMic(echoCancellation: false)
        try Task.checkCancellation()
        // Process-tap + aggregate device creation blocks for seconds on some
        // machines; never do it on the main actor (Record → Not Responding).
        await session.startSystemTapOnControlQueue()
        try Task.checkCancellation()
        guard startingSession === session else { throw CancellationError() }
        session.installListeners()
        if session.systemAudioError != nil {
            systemAudioWarning =
                "System audio capture failed - only your microphone is being recorded. "
                + "Check System Settings > Privacy & Security > Screen & System Audio Recording."
        } else {
            systemAudioWarning = nil
        }
        self.session = session
        startingSession = nil
        self.startedAt = .now
        self.isRecording = true
        watchForDeadChannels(session: session, echoCancellationWasOn: false)
        return session
    }

    private func watchForDeadChannels(session: RecordingSession, echoCancellationWasOn: Bool) {
        channelWatchTask?.cancel()
        channelWatchTask = Task { [weak self, weak session] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, let session, self.session === session, self.isRecording else { return }
            if session.micBufferCount == 0, echoCancellationWasOn {
                session.restartMic(recreateFile: true)
                micWarning = "Echo cancellation isn't working on this setup — continuing without it."
            }

            var tapRestarts = 0
            var micRestarts = 0
            var lastMicCount = 0
            var micStallTicks = 0
            while !Task.isCancelled, self.session === session, self.isRecording {
                try? await Task.sleep(for: .seconds(5))
                guard self.session === session, self.isRecording else { return }

                // The mic tap delivers buffers continuously even during silence, so a
                // flat count means the route genuinely died. The system tap only flows
                // while audio plays, so a flat system count is valid silence.
                let micCount = session.micBufferCount
                if micCount == 0 {
                    micWarning =
                        "No microphone audio is arriving. Check System Settings > Privacy & "
                        + "Security > Microphone, then stop and start a new recording."
                } else {
                    micStallTicks = micCount == lastMicCount ? micStallTicks + 1 : 0
                    if micStallTicks >= 2 {
                        if micRestarts < 8 {
                            // Recreate the file only when it stalled early enough that
                            // nothing usable was captured; otherwise keep prior audio.
                            session.restartMic(recreateFile: micCount < 100)
                            micRestarts += 1
                            micStallTicks = 0
                            micWarning =
                                "Microphone audio stalled — restarted capture without echo "
                                + "cancellation."
                        } else {
                            micWarning =
                                "Microphone audio stopped and couldn't be recovered. Stop and "
                                + "start a new recording."
                        }
                    } else if session.micNonSilentCount == 0, micCount > 200 {
                        micWarning =
                            "Microphone is recording but completely silent — check the input "
                            + "device and that the mic isn't muted, then start a new recording."
                    } else if session.micNonSilentCount > 0 {
                        micWarning = nil
                    }
                }
                lastMicCount = micCount

                let systemCount = session.systemBufferCount
                if SystemTapRetryPolicy.shouldRetry(
                    bufferCount: systemCount, attempts: tapRestarts)
                {
                    // One bounded retry recovers a grant completed during startup
                    // without recreating a silent system tap indefinitely.
                    session.restartSystemTap()
                    tapRestarts += 1
                    systemAudioWarning =
                        "No system audio captured yet — it only flows while sound is playing. "
                        + "Grant Screen & System Audio Recording permission, then stop and start "
                        + "a new recording."
                } else if session.systemNonSilentCount == 0, systemCount > 200 {
                    systemAudioWarning =
                        "System audio is arriving but completely silent — macOS may have denied "
                        + "the permission. Check System Settings > Privacy & Security > Screen & "
                        + "System Audio Recording, then stop and start a new recording."
                } else if session.systemNonSilentCount > 0 {
                    systemAudioWarning = nil
                }
            }
        }
    }

    func stop() async -> (micURL: URL, systemURL: URL)? {
        guard let activeSession = session ?? startingSession, !isStopping else { return nil }
        isStopping = true
        defer { isStopping = false }
        channelWatchTask?.cancel()
        channelWatchTask = nil
        await activeSession.stop()
        let urls = (activeSession.micURL, activeSession.systemURL)
        self.session = nil
        startingSession = nil
        meetingID = nil
        startedAt = nil
        isRecording = false
        isStarting = false
        micLevel = 0
        systemLevel = 0
        systemAudioWarning = nil
        micWarning = nil
        return urls
    }
}
