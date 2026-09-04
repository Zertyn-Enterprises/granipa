import AVFoundation
import CoreAudio
import Synchronization
import os

// File-writing state is queue-confined: micFile, micFramesWritten,
// micConverter and micPadSeconds (mic), systemFile and systemFramesWritten
// (system) are touched only on the writer queue. The recorders themselves
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

    private var micFile: AVAudioFile?
    private var micFramesWritten: AVAudioFramePosition = 0
    // Writer-queue-confined: converts buffers whose format differs from the
    // mic file after the input device changed mid-meeting.
    private var micConverter = BufferConverter()
    private var micPadSeconds: Double = 0
    private var systemFile: AVAudioFile?
    private var systemFramesWritten: AVAudioFramePosition = 0
    private var sessionStartHostSeconds: Double = 0
    private(set) var systemAudioError: Error?
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

    init(
        meetingID: String,
        directory: URL,
        fanOutChunks: Bool = true,
        onLevel: @escaping @Sendable (AudioChannel, Float) -> Void
    ) {
        self.meetingID = meetingID
        self.micURL = directory.appendingPathComponent("mic.m4a")
        self.systemURL = directory.appendingPathComponent("system.m4a")
        self.fanOutChunks = fanOutChunks
        self.onLevel = onLevel
        (micChunks, micContinuation) = AsyncStream.makeStream(of: AudioChunk.self)
        (systemChunks, systemContinuation) = AsyncStream.makeStream(of: AudioChunk.self)
    }

    func start(echoCancellation: Bool) throws {
        try startMic(echoCancellation: echoCancellation)
        startSystemTap()
        installListeners()
    }

    func startMic(echoCancellation: Bool) throws {
        sessionStartHostSeconds = AVAudioTime.seconds(forHostTime: mach_absolute_time())
        try mic.start(echoCancellation: echoCancellation) { [weak self] buffer, time in
            self?.handleMic(buffer, time: time)
        }
    }

    func startSystemTap() {
        do {
            try tap.start { [weak self] buffer, timestamp in
                self?.handleSystem(buffer, timestamp: timestamp)
            }
            systemAudioError = nil
        } catch {
            systemAudioError = error
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
    // Test seam: injects a mic chunk into the writer path without audio
    // hardware. startSeconds is meeting-relative, like handleMic's clock.
    func ingestMicBufferForTesting(_ buffer: AVAudioPCMBuffer, startSeconds: Double?) {
        writer.sync { writeMic(buffer, startSeconds: startSeconds) }
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
        do {
            try tap.start { [weak self] buffer, timestamp in
                self?.handleSystem(buffer, timestamp: timestamp)
            }
            systemAudioError = nil
        } catch {
            systemAudioError = error
        }
    }

    // Recovery for a dead or stalled mic: voice processing produces no callbacks on
    // some setups, an engine can start before the mic TCC grant, and routes die
    // mid-meeting. Restart without voice processing (the reliable path). When the
    // mic stalled before capturing anything usable, recreate the file and pad it to
    // the current meeting time so "file time == meeting time" stays true across the
    // gap; otherwise keep appending to preserve already-recorded audio.
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
                self?.micFile = nil
                self?.micFramesWritten = 0
                self?.micPadSeconds = pad
            }
        }
        mic = MicRecorder()
        try? mic.start(echoCancellation: false) { [weak self] buffer, time in
            self?.handleMic(buffer, time: time)
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
                    micFile = nil
                    systemFile = nil
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
            self?.writeMic(chunk.buffer, startSeconds: chunk.startSeconds)
        }
    }

    // Only frames that were actually written are counted (and reported), so a
    // failed write leaves the gap owed and the next buffer pads it again.
    @discardableResult
    private func appendSilence(
        to file: AVAudioFile, seconds: Double, format: AVAudioFormat
    ) -> AVAudioFramePosition {
        var remaining = AVAudioFramePosition((seconds * format.sampleRate).rounded())
        var appended: AVAudioFramePosition = 0
        while remaining > 0 {
            let chunkFrames = AVAudioFrameCount(min(remaining, 16_384))
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames)
            else { break }
            silence.frameLength = chunkFrames
            do {
                try file.write(from: silence)
            } catch {
                Self.log.error("mic silence write failed: \(String(describing: error))")
                break
            }
            remaining -= AVAudioFramePosition(chunkFrames)
            appended += AVAudioFramePosition(chunkFrames)
        }
        return appended
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
            self?.writeSystem(chunk.buffer, startSeconds: chunk.startSeconds)
        }
    }

    // The mic file keeps the format of its first buffer for the whole meeting;
    // after the input device switches mid-meeting, later buffers may arrive at
    // a different sample rate or channel count and are converted into the
    // file's processing format instead of being dropped. Gaps (restart,
    // stalled route) are padded with silence so file time == meeting time,
    // mirroring writeSystem.
    private func writeMic(_ buffer: AVAudioPCMBuffer, startSeconds: Double?) {
        if micFile == nil {
            micFile = Self.openAudioFile(url: micURL, format: buffer.format, bitRate: 96_000)
            if let file = micFile, micPadSeconds > 0 {
                micFramesWritten += appendSilence(
                    to: file, seconds: micPadSeconds, format: buffer.format)
            }
            micPadSeconds = 0
        }
        guard let file = micFile else { return }
        let fileFormat = file.processingFormat
        if let start = startSeconds, start > 0 {
            let expectedFrame = AVAudioFramePosition((start * fileFormat.sampleRate).rounded())
            let gap = expectedFrame - micFramesWritten
            if gap > AVAudioFramePosition(fileFormat.sampleRate * 0.25) {
                micFramesWritten += appendSilence(
                    to: file, seconds: Double(gap) / fileFormat.sampleRate, format: fileFormat)
            }
        }
        let toWrite: AVAudioPCMBuffer
        if buffer.format == fileFormat {
            toWrite = buffer
        } else {
            do {
                toWrite = try micConverter.convert(buffer, to: fileFormat)
            } catch {
                Self.log.error(
                    "mic buffer dropped: conversion \(buffer.format.sampleRate)Hz/\(buffer.format.channelCount)ch -> \(fileFormat.sampleRate)Hz/\(fileFormat.channelCount)ch failed: \(String(describing: error))")
                return
            }
        }
        do {
            try file.write(from: toWrite)
            micFramesWritten += AVAudioFramePosition(toWrite.frameLength)
        } catch {
            Self.log.error("mic write failed: \(String(describing: error))")
        }
    }

    private func writeSystem(_ buffer: AVAudioPCMBuffer, startSeconds: Double?) {
        let sampleRate = buffer.format.sampleRate
        if systemFile == nil {
            systemFile = Self.openAudioFile(url: systemURL, format: buffer.format, bitRate: 128_000)
        }
        if let file = systemFile, let start = startSeconds, start > 0 {
            let expectedFrame = AVAudioFramePosition((start * sampleRate).rounded())
            var gap = expectedFrame - systemFramesWritten
            if gap > AVAudioFramePosition(sampleRate * 0.25) {
                while gap > 0 {
                    let chunkFrames = AVAudioFrameCount(min(gap, 16_384))
                    guard
                        let silence = AVAudioPCMBuffer(
                            pcmFormat: buffer.format, frameCapacity: chunkFrames)
                    else { break }
                    silence.frameLength = chunkFrames
                    try? file.write(from: silence)
                    systemFramesWritten += AVAudioFramePosition(chunkFrames)
                    gap -= AVAudioFramePosition(chunkFrames)
                }
            }
        }
        try? systemFile?.write(from: buffer)
        systemFramesWritten += AVAudioFramePosition(buffer.frameLength)
    }

    private static func openAudioFile(url: URL, format: AVAudioFormat, bitRate: Int) -> AVAudioFile?
    {
        try? AVAudioFile(
            forWriting: url,
            settings: aacSettings(for: format, bitRate: bitRate),
            commonFormat: format.commonFormat,
            interleaved: format.isInterleaved)
    }

    private static func aacSettings(for format: AVAudioFormat, bitRate: Int) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: Int(format.channelCount),
            AVEncoderBitRateKey: bitRate,
        ]
    }
}
