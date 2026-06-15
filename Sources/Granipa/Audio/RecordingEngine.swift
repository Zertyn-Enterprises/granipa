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
                session.restartMic(recreateFile: true)
                micWarning = "Echo cancellation isn't working on this setup — continuing without it."
            }

            var tapRestarts = 0
            var lastSystemCount = 0
            var stallTicks = 0
            var micRestarts = 0
            var lastMicCount = 0
            var micStallTicks = 0
            while !Task.isCancelled, self.session === session, self.isRecording {
                try? await Task.sleep(for: .seconds(5))
                guard self.session === session, self.isRecording else { return }

                // Buffers flowed and then stopped: route died without a device-change
                // notification (e.g. sample-rate renegotiation). Rebuild as backstop.
                let systemCount = session.systemBufferCount
                if systemCount > 0 {
                    stallTicks = systemCount == lastSystemCount ? stallTicks + 1 : 0
                    if stallTicks >= 3 {
                        session.restartSystemTap()
                        stallTicks = 0
                    }
                }
                lastSystemCount = systemCount

                // The mic tap delivers buffers continuously even during silence, so a
                // flat count means the route genuinely died (unlike the system tap,
                // which only flows while audio plays — hence the lower stall threshold).
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

                if session.systemBufferCount == 0 {
                    // A tap created before the permission grant stays dead forever;
                    // recreating it picks the grant up mid-recording.
                    if tapRestarts < 8 {
                        session.restartSystemTap()
                        tapRestarts += 1
                    }
                    systemAudioWarning =
                        "No system audio captured yet — it only flows while sound is playing. "
                        + "If macOS just asked for the permission, grant it and keep recording: "
                        + "capture starts by itself."
                } else if session.systemNonSilentCount == 0, session.systemBufferCount > 200 {
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
