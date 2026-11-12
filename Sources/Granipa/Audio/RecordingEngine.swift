import Foundation
import Observation

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

    /// Both capture warnings in one string, for surfaces with room for one.
    var captureWarningText: String? {
        let text = [micWarning, systemAudioWarning].compactMap { $0 }.joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

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
        systemAudioWarning = session.systemTapFailed ? SystemAudioIssue.startFailedMessage : nil
        self.session = session
        startingSession = nil
        self.startedAt = .now
        self.isRecording = true
        watchForDeadChannels(session: session)
        return session
    }

    private func watchForDeadChannels(session: RecordingSession) {
        channelWatchTask?.cancel()
        channelWatchTask = Task { [weak self, weak session] in
            guard let self, let session else { return }
            var mic = MicHealthWatch()
            var system = SystemHealthWatch()
            while !Task.isCancelled, self.session === session, self.isRecording {
                try? await Task.sleep(for: .seconds(5))
                guard self.session === session, self.isRecording else { return }
                checkMic(session, &mic)
                checkSystem(session, &system)
            }
        }
    }

    private func checkMic(_ session: RecordingSession, _ watch: inout MicHealthWatch) {
        let verdict = watch.tick(
            ChannelSample(
                buffers: session.micBufferCount, nonSilent: session.micNonSilentCount,
                framesWritten: session.micFramesWritten, startFailed: session.micStartFailed))
        if let recreateFile = verdict.restartRecreatingFile {
            session.restartMic(recreateFile: recreateFile)
        }
        switch verdict.warning {
        case .keep: break
        case .clear: micWarning = nil
        case .show(let issue): micWarning = issue.message
        }
    }

    private func checkSystem(_ session: RecordingSession, _ watch: inout SystemHealthWatch) {
        let verdict = watch.tick(
            ChannelSample(
                buffers: session.systemBufferCount, nonSilent: session.systemNonSilentCount,
                framesWritten: session.systemFramesWritten, startFailed: session.systemTapFailed),
            elapsed: startedAt.map { Date.now.timeIntervalSince($0) } ?? 0)
        if verdict.restartTap {
            session.restartSystemTap()
        }
        systemAudioWarning = verdict.issue?.message
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
