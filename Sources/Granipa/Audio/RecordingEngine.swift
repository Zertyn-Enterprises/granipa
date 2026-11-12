import Foundation
import Observation

enum SystemTapRetryPolicy {
    /// Retries of a tap that started but never delivered: recovers a grant
    /// completed during startup without recreating a silent tap indefinitely.
    static let maxSilentAttempts = 1
    /// Retries of a tap whose start or restart threw (e.g. after a device switch).
    static let maxFailedAttempts = 3
    /// The tap only delivers while sound plays, so a quiet start is normal;
    /// only after two minutes without any system audio is the user told to
    /// check the permission and restart.
    static let missingWarningSeconds: TimeInterval = 120

    static func shouldRetry(tapFailed: Bool, bufferCount: Int, attempts: Int) -> Bool {
        if tapFailed { return attempts < maxFailedAttempts }
        return bufferCount == 0 && attempts < maxSilentAttempts
    }
}

/// "Recording but silent" judged over the last 30 s instead of the whole
/// meeting, so a mic that goes dead after it once worked still warns.
struct MicSilenceWindow {
    /// Watchdog ticks spanned by the window (6 × 5 s).
    static let ticks = 6
    /// Fewer buffers than this in the window is a stalled route, which the
    /// stall check owns.
    static let minBuffers = 50
    private var samples: [(buffers: Int, nonSilent: Int)] = []

    /// Records the running totals at one tick; true when the full window held
    /// buffers but none of them carried sound.
    mutating func record(buffers: Int, nonSilent: Int) -> Bool {
        samples.append((buffers, nonSilent))
        if samples.count > Self.ticks + 1 { samples.removeFirst() }
        guard samples.count == Self.ticks + 1, let oldest = samples.first else { return false }
        return nonSilent == oldest.nonSilent && buffers - oldest.buffers >= Self.minBuffers
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

    private static let systemTapFailedWarning =
        "System audio capture failed - only your microphone is being recorded. "
        + "Check System Settings > Privacy & Security > Screen & System Audio Recording."

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
        await Task.yield()
        try Task.checkCancellation()
        try session.startMic()
        try Task.checkCancellation()
        // Process-tap + aggregate device creation blocks for seconds on some
        // machines; never do it on the main actor (Record → Not Responding).
        await session.startSystemTapOnControlQueue()
        try Task.checkCancellation()
        guard startingSession === session else { throw CancellationError() }
        session.installListeners()
        systemAudioWarning = session.systemTapFailed ? Self.systemTapFailedWarning : nil
        self.session = session
        startingSession = nil
        self.startedAt = .now
        self.isRecording = true
        watchForDeadChannels(session: session)
        return session
    }

    private struct MicWatch {
        var restarts = 0
        var lastCount = 0
        var lastFrames: Int64 = 0
        var stallTicks = 0
        var unsavedTicks = 0
        var silence = MicSilenceWindow()
    }

    private struct SystemWatch {
        var silentRetries = 0
        var failedRetries = 0
        var lastCount = 0
        var lastFrames: Int64 = 0
        var unsavedTicks = 0
    }

    private static let maxMicRestarts = 8

    private func watchForDeadChannels(session: RecordingSession) {
        channelWatchTask?.cancel()
        channelWatchTask = Task { [weak self, weak session] in
            guard let self, let session else { return }
            var mic = MicWatch()
            var system = SystemWatch()
            while !Task.isCancelled, self.session === session, self.isRecording {
                try? await Task.sleep(for: .seconds(5))
                guard self.session === session, self.isRecording else { return }
                checkMic(session, &mic)
                checkSystem(session, &system)
            }
        }
    }

    // The mic tap delivers buffers continuously even during silence, so a flat
    // count means the route genuinely died. Buffers arriving while the written
    // frame count stays flat means the file is not recording them.
    private func checkMic(_ session: RecordingSession, _ watch: inout MicWatch) {
        let count = session.micBufferCount
        let frames = session.micFramesWritten
        let arrived = count > watch.lastCount
        let saved = frames > watch.lastFrames
        watch.stallTicks = arrived ? 0 : watch.stallTicks + 1
        watch.unsavedTicks = arrived && !saved ? watch.unsavedTicks + 1 : 0
        let silent = watch.silence.record(buffers: count, nonSilent: session.micNonSilentCount)
        watch.lastCount = count
        watch.lastFrames = frames

        let startFailed = session.micStartFailed
        if startFailed || (count > 0 && watch.stallTicks >= 2) {
            guard watch.restarts < Self.maxMicRestarts else {
                micWarning =
                    "Microphone audio stopped and couldn't be recovered. Stop and start a new "
                    + "recording."
                return
            }
            // Recreate the file only when it stalled early enough that nothing
            // usable was captured; otherwise keep prior audio.
            session.restartMic(recreateFile: count < 100)
            watch.restarts += 1
            watch.stallTicks = 0
            micWarning =
                startFailed
                ? "Microphone couldn't be restarted — trying again."
                : "Microphone audio stalled — restarting capture."
        } else if count == 0 {
            micWarning =
                "No microphone audio is arriving. Check System Settings > Privacy & "
                + "Security > Microphone, then stop and start a new recording."
        } else if watch.unsavedTicks >= 2 {
            micWarning =
                "Microphone audio is arriving but isn't being saved — your voice is missing "
                + "from this recording. Stop and start a new recording."
        } else if silent {
            micWarning =
                "Microphone is recording but completely silent — check the input "
                + "device and that the mic isn't muted, then start a new recording."
        } else if arrived {
            micWarning = nil
            if saved { watch.restarts = 0 }
        }
    }

    // The system tap only flows while audio plays, so a flat or zero count is
    // valid silence until it lasts far longer than a quiet meeting start.
    private func checkSystem(_ session: RecordingSession, _ watch: inout SystemWatch) {
        let count = session.systemBufferCount
        let frames = session.systemFramesWritten
        watch.unsavedTicks =
            count > watch.lastCount && frames == watch.lastFrames ? watch.unsavedTicks + 1 : 0
        watch.lastCount = count
        watch.lastFrames = frames

        let tapFailed = session.systemTapFailed
        if !tapFailed { watch.failedRetries = 0 }
        let retry = SystemTapRetryPolicy.shouldRetry(
            tapFailed: tapFailed, bufferCount: count,
            attempts: tapFailed ? watch.failedRetries : watch.silentRetries)
        if retry {
            session.restartSystemTap()
            if tapFailed { watch.failedRetries += 1 } else { watch.silentRetries += 1 }
        }

        let elapsed = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        if tapFailed {
            systemAudioWarning =
                retry
                ? "System audio capture stopped — retrying. Only your microphone is being "
                    + "recorded until it recovers."
                : Self.systemTapFailedWarning + " Then stop and start a new recording."
        } else if watch.unsavedTicks >= 2 {
            systemAudioWarning =
                "System audio is arriving but isn't being saved — the other side is missing "
                + "from this recording. Stop and start a new recording."
        } else if count == 0 {
            systemAudioWarning =
                elapsed >= SystemTapRetryPolicy.missingWarningSeconds
                ? "No system audio captured in the first 2 minutes. If others have spoken, "
                    + "grant Screen & System Audio Recording permission, then stop and start a "
                    + "new recording."
                : nil
        } else if session.systemNonSilentCount == 0, count > 200 {
            systemAudioWarning =
                "System audio is arriving but completely silent — macOS may have denied "
                + "the permission. Check System Settings > Privacy & Security > Screen & "
                + "System Audio Recording, then stop and start a new recording."
        } else {
            systemAudioWarning = nil
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
