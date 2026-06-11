import Foundation
import Observation

@MainActor
@Observable
final class RecordingEngine {
    private(set) var isRecording = false
    private(set) var meetingID: String?
    private(set) var startedAt: Date?
    private(set) var micLevel: Float = 0
    private(set) var systemLevel: Float = 0
    private(set) var systemAudioWarning: String?
    private(set) var micWarning: String?

    private(set) var session: RecordingSession?

    func start(meetingID: String) throws -> RecordingSession {
        guard !isRecording else {
            throw NSError(
                domain: "Granipa", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Already recording another meeting."])
        }
        let directory = try AppPaths.audioDirectory(meetingID: meetingID)
        let session = RecordingSession(meetingID: meetingID, directory: directory) {
            [weak self] channel, level in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch channel {
                case .mic: micLevel = level
                case .system: systemLevel = level
                }
            }
        }
        let echoCancellation = UserDefaults.standard.object(forKey: "echoCancellation") as? Bool ?? true
        try session.start(echoCancellation: echoCancellation)
        if session.systemAudioError != nil {
            systemAudioWarning =
                "System audio capture failed - only your microphone is being recorded. "
                + "Check System Settings > Privacy & Security > Screen & System Audio Recording."
        } else {
            systemAudioWarning = nil
        }
        self.session = session
        self.meetingID = meetingID
        self.startedAt = .now
        self.isRecording = true
        watchForDeadChannels(session: session, echoCancellationWasOn: echoCancellation)
        return session
    }

    private func watchForDeadChannels(session: RecordingSession, echoCancellationWasOn: Bool) {
        Task { [weak self, weak session] in
            try? await Task.sleep(for: .seconds(3))
            guard let self, let session, self.session === session, self.isRecording else { return }
            if session.micBufferCount == 0, echoCancellationWasOn {
                session.restartMicWithoutEchoCancellation()
                micWarning = "Echo cancellation isn't working on this setup — continuing without it."
            }

            try? await Task.sleep(for: .seconds(5))
            guard self.session === session, self.isRecording else { return }
            if session.micBufferCount == 0 {
                micWarning =
                    "No microphone audio is arriving. Check System Settings > Privacy & Security "
                    + "> Microphone, then stop and start a new recording."
            } else if session.micBufferCount > 0, micWarning?.hasPrefix("No microphone") == true {
                micWarning = nil
            }
            if session.systemBufferCount == 0, session.systemAudioError == nil {
                systemAudioWarning =
                    "No system audio captured yet — it only flows while sound is playing. "
                    + "If you just granted the permission, stop and start a new recording."
            }
        }
    }

    func stop() -> (micURL: URL, systemURL: URL)? {
        guard let session else { return nil }
        session.stop()
        let urls = (session.micURL, session.systemURL)
        self.session = nil
        meetingID = nil
        startedAt = nil
        isRecording = false
        micLevel = 0
        systemLevel = 0
        systemAudioWarning = nil
        micWarning = nil
        return urls
    }
}
