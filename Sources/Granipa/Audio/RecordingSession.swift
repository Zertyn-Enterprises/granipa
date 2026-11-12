import AVFoundation
import CoreAudio
import Synchronization
import os

// File-writing state is queue-confined: micWriter and systemWriter are
// touched only on the writer queue (except their thread-safe frame counts).
// The recorders themselves
// keep their pre-existing, not fully queue-confined ownership: started from
// the caller's thread, restarted and stopped on controlQueue, and never
// touched from their tap callback threads. Capture lifecycle operations are
// serialized on controlQueue.
final class RecordingSession: @unchecked Sendable {
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "session")
    let meetingID: String
    let micURL: URL
    let systemURL: URL
    let micChunks: AsyncStream<AudioChunk>
    let systemChunks: AsyncStream<AudioChunk>

    private let micContinuation: AsyncStream<AudioChunk>.Continuation
    private let systemContinuation: AsyncStream<AudioChunk>.Continuation
    private var mic = MicRecorder()
    private let tap = SystemAudioTap()
    private let micBuffers = Mutex(0)
    private let micNonSilent = Mutex(0)
    private let systemBuffers = Mutex(0)
    private let systemNonSilent = Mutex(0)
    private let onLevel: @Sendable (AudioChannel, Float) -> Void
    private let fanOutChunks: Bool
    private let controlQueue = DispatchQueue(
        label: "com.zertyn.granipa.session-control", qos: .utility)
    private let writer = DispatchQueue(label: "com.zertyn.granipa.session-write")
    private let controlState = Mutex(ControlState())

    private let micWriter: ChannelFileWriter
    private let systemWriter: ChannelFileWriter
    private var sessionStartHostSeconds: Double = 0
    // Whether the latest start or restart of each recorder threw; read by the
    // watchdog, written on the control queue.
    private let micStartFailure = Mutex(false)
    private let systemTapFailure = Mutex(false)
    private var deviceChangeListener: AudioObjectPropertyListenerBlock?
    private var inputDeviceChangeListener: AudioObjectPropertyListenerBlock?

    private struct ControlState {
        var isStopping = false
        var micRestartPending = false
        var systemRestartPending = false
    }

    var micBufferCount: Int { micBuffers.withLock { $0 } }
    var micNonSilentCount: Int { micNonSilent.withLock { $0 } }
    var systemBufferCount: Int { systemBuffers.withLock { $0 } }
    var systemNonSilentCount: Int { systemNonSilent.withLock { $0 } }
    var micFramesWritten: AVAudioFramePosition { micWriter.audioFramesWritten }
    var systemFramesWritten: AVAudioFramePosition { systemWriter.audioFramesWritten }
    var micStartFailed: Bool { micStartFailure.withLock { $0 } }
    var systemTapFailed: Bool { systemTapFailure.withLock { $0 } }

    init(
        meetingID: String,
        directory: URL,
        fanOutChunks: Bool = true,
        onLevel: @escaping @Sendable (AudioChannel, Float) -> Void
    ) {
        self.meetingID = meetingID
        let micURL = directory.appendingPathComponent("mic.m4a")
        let systemURL = directory.appendingPathComponent("system.m4a")
        self.micURL = micURL
        self.systemURL = systemURL
        micWriter = ChannelFileWriter(url: micURL, bitRate: 96_000)
        systemWriter = ChannelFileWriter(url: systemURL, bitRate: 128_000)
        self.fanOutChunks = fanOutChunks
        self.onLevel = onLevel
        (micChunks, micContinuation) = AsyncStream.makeStream(of: AudioChunk.self)
        (systemChunks, systemContinuation) = AsyncStream.makeStream(of: AudioChunk.self)
    }

    // Meetings never use voice processing: AEC on the input node pegs a core
    // and hangs Record (pid 25501: 134% CPU, 8 hangs) even with live ASR off.
    func startMic() throws {
        sessionStartHostSeconds = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        try startMicRecorder()
    }

    // A configuration change stops the engine; restarting keeps appending to
    // the same file, like a default-input switch.
    private func startMicRecorder() throws {
        try recordMicStart {
            try mic.start(
                echoCancellation: false,
                onBuffer: { [weak self] buffer, time in
                    self?.handleMic(buffer, time: time)
                },
                onConfigurationChange: { [weak self] in
                    self?.restartMic(recreateFile: false)
                })
        }
    }

    private func recordMicStart(_ start: () throws -> Void) throws {
        do {
            try start()
            micStartFailure.withLock { $0 = false }
        } catch {
            micStartFailure.withLock { $0 = true }
            throw error
        }
    }

    func startSystemTap() {
        do {
            try tap.start { [weak self] buffer, timestamp in
                self?.handleSystem(buffer, timestamp: timestamp)
            }
            systemTapFailure.withLock { $0 = false }
        } catch {
            Self.log.error("system tap start failed: \(String(describing: error), privacy: .public)")
            systemTapFailure.withLock { $0 = true }
        }
    }

    func startSystemTapOnControlQueue() async {
        await withCheckedContinuation { continuation in
            controlQueue.async { [self] in
                let shouldStart = controlState.withLock { !$0.isStopping }
                if shouldStart {
                    startSystemTap()
                }
                continuation.resume()
            }
        }
    }

    func installListeners() {
        installDeviceChangeListener()
    }

    // Switching outputs mid-meeting (AirPods connecting, HDMI plugged in)
    // invalidates the tap's aggregate; rebuild it on the new device.
    private func installDeviceChangeListener() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.restartSystemTap()
        }
        deviceChangeListener = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)

        // The mic engine stays bound to the input device it started on; when the
        // default input switches (AirPods in or out, a wired headset, a USB mic)
        // the old device stops delivering. Restart the mic onto the new default.
        var inputAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let inputBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.restartMicForDefaultInputChange()
        }
        inputDeviceChangeListener = inputBlock
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &inputAddress, DispatchQueue.main, inputBlock)
    }

    // A default-input switch must keep appending to the same mic file:
    // recreating it replaced everything recorded so far with silence.
    private func restartMicForDefaultInputChange() {
        restartMic(recreateFile: false)
    }

#if DEBUG
    // Test seams: inject a chunk into a channel's writer path, or a mic start
    // result, without audio hardware. startSeconds is meeting-relative, like handleMic's clock.
    func ingestMicBufferForTesting(_ buffer: AVAudioPCMBuffer, startSeconds: Double?) {
        writer.sync { micWriter.write(buffer, startSeconds: startSeconds) }
    }

    func recordMicStartForTesting(_ start: () throws -> Void) throws {
        try recordMicStart(start)
    }

    func ingestSystemBufferForTesting(_ buffer: AVAudioPCMBuffer, startSeconds: Double?) {
        writer.sync { systemWriter.write(buffer, startSeconds: startSeconds) }
    }
#endif

    private func removeDeviceChangeListener() {
        if let block = deviceChangeListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
            deviceChangeListener = nil
        }
        if let block = inputDeviceChangeListener {
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultInputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
            inputDeviceChangeListener = nil
        }
    }

    // A tap created before the system-audio TCC grant never delivers buffers;
    // tearing it down and recreating it picks the grant up without touching the
    // mic. Timing stays correct: gaps are padded with silence on the next buffer.
    func restartSystemTap() {
        let shouldSchedule = controlState.withLock { state in
            guard !state.isStopping, !state.systemRestartPending else { return false }
            state.systemRestartPending = true
            return true
        }
        guard shouldSchedule else { return }
        controlQueue.async { [weak self] in
            guard let self else { return }
            let shouldRestart = self.controlState.withLock { !$0.isStopping }
            if shouldRestart {
                self.performSystemTapRestart()
            }
            self.controlState.withLock { $0.systemRestartPending = false }
        }
    }

    private func performSystemTapRestart() {
        Self.log.info("restarting system tap (buffers so far: \(self.systemBufferCount))")
        tap.stop()
        startSystemTap()
    }

    // Recovery for a mic that stopped delivering after it had started (a route
    // that died or stalled mid-meeting, an input switch or reconfiguration) or
    // whose last restart threw. The stall check needs at least one buffer, so a
    // mic that never delivered (e.g. no mic permission) is only warned about,
    // not restarted. When the mic stalled before capturing anything usable,
    // recreate the file and pad it to the current meeting time so "file time ==
    // meeting time" stays true across the gap; otherwise keep appending to
    // preserve already-recorded audio.
    func restartMic(recreateFile: Bool) {
        let shouldSchedule = controlState.withLock { state in
            guard !state.isStopping, !state.micRestartPending else { return false }
            state.micRestartPending = true
            return true
        }
        guard shouldSchedule else { return }
        controlQueue.async { [weak self] in
            guard let self else { return }
            let shouldRestart = self.controlState.withLock { !$0.isStopping }
            if shouldRestart {
                self.performMicRestart(recreateFile: recreateFile)
            }
            self.controlState.withLock { $0.micRestartPending = false }
        }
    }

    private func performMicRestart(recreateFile: Bool) {
        mic.stop()
        if recreateFile {
            let pad =
                AVAudioTime.seconds(forHostTime: mach_absolute_time()) - sessionStartHostSeconds
            writer.async { [weak self] in
                self?.micWriter.reset(padSeconds: pad)
            }
        }
        mic = MicRecorder()
        do {
            try startMicRecorder()
        } catch {
            Self.log.error("mic restart failed: \(String(describing: error), privacy: .public)")
        }
    }

    func stop() async {
        controlState.withLock { $0.isStopping = true }
        await withCheckedContinuation { continuation in
            controlQueue.async { [self] in
                removeDeviceChangeListener()
                mic.stop()
                tap.stop()
                writer.sync {
                    micWriter.close()
                    systemWriter.close()
                }
                micContinuation.finish()
                systemContinuation.finish()
                continuation.resume()
            }
        }
    }

    private func handleMic(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        let count = micBuffers.withLock { count in
            count += 1
            return count
        }
        if count == 1 {
            Self.log.info("first mic buffer: \(buffer.format.sampleRate)Hz")
        }
        let level = buffer.rmsLevel
        if level > 0.0005 {
            micNonSilent.withLock { $0 += 1 }
        }
        onLevel(.mic, level)
        guard let copy = buffer.deepCopy() else { return }
        let host = time.isHostTimeValid ? time.hostTime : mach_absolute_time()
        let startSeconds =
            AVAudioTime.seconds(forHostTime: host) - sessionStartHostSeconds
        let chunk = AudioChunk(buffer: copy, startSeconds: startSeconds)
        if fanOutChunks {
            micContinuation.yield(chunk)
        }
        writer.async { [weak self] in
            self?.micWriter.write(chunk.buffer, startSeconds: chunk.startSeconds)
        }
    }

    private func handleSystem(_ buffer: AVAudioPCMBuffer, timestamp: AudioTimeStamp) {
        let count = systemBuffers.withLock { count in
            count += 1
            return count
        }
        if count == 1 {
            Self.log.info("first system buffer: \(buffer.format.sampleRate)Hz")
        }
        let level = buffer.rmsLevel
        if level > 0.0005 {
            systemNonSilent.withLock { $0 += 1 }
        }
        onLevel(.system, level)
        guard let copy = buffer.deepCopy() else { return }
        var startSeconds: Double?
        if timestamp.mFlags.contains(.hostTimeValid) {
            startSeconds =
                AVAudioTime.seconds(forHostTime: timestamp.mHostTime) - sessionStartHostSeconds
        }
        let chunk = AudioChunk(buffer: copy, startSeconds: startSeconds)
        if fanOutChunks {
            systemContinuation.yield(chunk)
        }
        writer.async { [weak self] in
            self?.systemWriter.write(chunk.buffer, startSeconds: chunk.startSeconds)
        }
    }
}
