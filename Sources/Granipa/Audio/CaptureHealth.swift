import Foundation

// Pure per-tick decisions of the recording watchdog. RecordingEngine samples
// the session every 5 s, feeds the running totals in and applies the verdict.

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

/// Running totals of one channel at a watchdog tick.
struct ChannelSample: Equatable {
    var buffers: Int
    var nonSilent: Int
    var framesWritten: Int64
    /// The latest start or restart of the channel's recorder threw.
    var startFailed = false
}

enum MicIssue: Equatable {
    case unrecoverable, restartFailed, stalled, noAudio, notSaved, silent

    var message: String {
        switch self {
        case .unrecoverable:
            "Microphone audio stopped and couldn't be recovered. Stop and start a new recording."
        case .restartFailed: "Microphone couldn't be restarted — trying again."
        case .stalled: "Microphone audio stalled — restarting capture."
        case .noAudio:
            "No microphone audio is arriving. Check System Settings > Privacy & "
                + "Security > Microphone, then stop and start a new recording."
        case .notSaved:
            "Microphone audio is arriving but isn't being saved — your voice is missing "
                + "from this recording. Stop and start a new recording."
        case .silent:
            "Microphone is recording but completely silent — check the input "
                + "device and that the mic isn't muted, then start a new recording."
        }
    }
}

/// The mic tap delivers buffers continuously even during silence, so a flat
/// count means the route genuinely died. Buffers arriving while the written
/// frame count stays flat means the file is not recording them.
struct MicHealthWatch {
    enum WarningUpdate: Equatable {
        case keep, clear
        case show(MicIssue)
    }

    struct Verdict: Equatable {
        /// nil: no restart; otherwise restart, recreating the file or not.
        var restartRecreatingFile: Bool?
        var warning: WarningUpdate
    }

    static let maxRestarts = 8
    private var restarts = 0
    private var lastBuffers = 0
    private var lastFrames: Int64 = 0
    private var stallTicks = 0
    private var unsavedTicks = 0
    private var silence = MicSilenceWindow()

    mutating func tick(_ sample: ChannelSample) -> Verdict {
        let arrived = sample.buffers > lastBuffers
        let saved = sample.framesWritten > lastFrames
        stallTicks = arrived ? 0 : stallTicks + 1
        unsavedTicks = arrived && !saved ? unsavedTicks + 1 : 0
        let silent = silence.record(buffers: sample.buffers, nonSilent: sample.nonSilent)
        lastBuffers = sample.buffers
        lastFrames = sample.framesWritten

        if sample.startFailed || (sample.buffers > 0 && stallTicks >= 2) {
            return restart(sample)
        }
        if let issue = issue(buffers: sample.buffers, silent: silent) {
            return Verdict(warning: .show(issue))
        }
        // Clear only on fresh audio: a flat tick may be a restart in progress.
        guard arrived else { return Verdict(warning: .keep) }
        if saved { restarts = 0 }
        return Verdict(warning: .clear)
    }

    private mutating func restart(_ sample: ChannelSample) -> Verdict {
        guard restarts < Self.maxRestarts else { return Verdict(warning: .show(.unrecoverable)) }
        restarts += 1
        stallTicks = 0
        // Recreate the file only when it stalled early enough that nothing
        // usable was captured; otherwise keep prior audio.
        return Verdict(
            restartRecreatingFile: sample.buffers < 100,
            warning: .show(sample.startFailed ? .restartFailed : .stalled))
    }

    private func issue(buffers: Int, silent: Bool) -> MicIssue? {
        if buffers == 0 { return .noAudio }
        if unsavedTicks >= 2 { return .notSaved }
        return silent ? .silent : nil
    }
}

enum SystemAudioIssue: Equatable {
    case tapRetrying, tapFailed, notSaved, missing, silent

    static let startFailedMessage =
        "System audio capture failed - only your microphone is being recorded. "
        + "Check System Settings > Privacy & Security > Screen & System Audio Recording."

    var message: String {
        switch self {
        case .tapRetrying:
            "System audio capture stopped — retrying. Only your microphone is being "
                + "recorded until it recovers."
        case .tapFailed: Self.startFailedMessage + " Then stop and start a new recording."
        case .notSaved:
            "System audio is arriving but isn't being saved — the other side is missing "
                + "from this recording. Stop and start a new recording."
        case .missing:
            "No system audio captured in the first 2 minutes. If others have spoken, "
                + "grant Screen & System Audio Recording permission, then stop and start a "
                + "new recording."
        case .silent:
            "System audio is arriving but completely silent — macOS may have denied "
                + "the permission. Check System Settings > Privacy & Security > Screen & "
                + "System Audio Recording, then stop and start a new recording."
        }
    }
}

/// The system tap only flows while audio plays, so a flat or zero count is
/// valid silence until it lasts far longer than a quiet meeting start.
struct SystemHealthWatch {
    struct Verdict: Equatable {
        var restartTap = false
        /// The warning to show; nil clears it.
        var issue: SystemAudioIssue?
    }

    private var silentRetries = 0
    private var failedRetries = 0
    private var lastBuffers = 0
    private var lastFrames: Int64 = 0
    private var unsavedTicks = 0

    mutating func tick(_ sample: ChannelSample, elapsed: TimeInterval) -> Verdict {
        let arrived = sample.buffers > lastBuffers
        unsavedTicks = arrived && sample.framesWritten == lastFrames ? unsavedTicks + 1 : 0
        lastBuffers = sample.buffers
        lastFrames = sample.framesWritten

        if !sample.startFailed { failedRetries = 0 }
        let retry = SystemTapRetryPolicy.shouldRetry(
            tapFailed: sample.startFailed, bufferCount: sample.buffers,
            attempts: sample.startFailed ? failedRetries : silentRetries)
        if retry, sample.startFailed { failedRetries += 1 }
        if retry, !sample.startFailed { silentRetries += 1 }
        return Verdict(restartTap: retry, issue: issue(sample, retried: retry, elapsed: elapsed))
    }

    private func issue(
        _ sample: ChannelSample, retried: Bool, elapsed: TimeInterval
    ) -> SystemAudioIssue? {
        if sample.startFailed { return retried ? .tapRetrying : .tapFailed }
        if unsavedTicks >= 2 { return .notSaved }
        if sample.buffers == 0 {
            return elapsed >= SystemTapRetryPolicy.missingWarningSeconds ? .missing : nil
        }
        return sample.nonSilent == 0 && sample.buffers > 200 ? .silent : nil
    }
}
