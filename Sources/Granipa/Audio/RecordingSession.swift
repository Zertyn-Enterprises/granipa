import AVFoundation
import CoreAudio
import Synchronization
import os

// Mutable state is queue-confined: mic* fields are touched only from the mic tap
// callback thread, system* fields only from the tap IO queue. start/stop run on
// the main actor after callbacks have ceased.
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

    private var micFile: AVAudioFile?
    private var micPadSeconds: Double = 0
    private var systemFile: AVAudioFile?
    private var systemFramesWritten: AVAudioFramePosition = 0
    private var sessionStartHostSeconds: Double = 0
    private(set) var systemAudioError: Error?
    private var deviceChangeListener: AudioObjectPropertyListenerBlock?
    private var inputDeviceChangeListener: AudioObjectPropertyListenerBlock?

    var micBufferCount: Int { micBuffers.withLock { $0 } }
    var micNonSilentCount: Int { micNonSilent.withLock { $0 } }
    var systemBufferCount: Int { systemBuffers.withLock { $0 } }
    var systemNonSilentCount: Int { systemNonSilent.withLock { $0 } }

    init(
        meetingID: String,
        directory: URL,
        onLevel: @escaping @Sendable (AudioChannel, Float) -> Void
    ) {
        self.meetingID = meetingID
        self.micURL = directory.appendingPathComponent("mic.m4a")
        self.systemURL = directory.appendingPathComponent("system.m4a")
        self.onLevel = onLevel
        (micChunks, micContinuation) = AsyncStream.makeStream(of: AudioChunk.self)
        (systemChunks, systemContinuation) = AsyncStream.makeStream(of: AudioChunk.self)
    }

    func start(echoCancellation: Bool) throws {
        sessionStartHostSeconds = AVAudioTime.seconds(forHostTime: mach_absolute_time())

        try mic.start(echoCancellation: echoCancellation) { [weak self] buffer in
            self?.handleMic(buffer)
        }

        do {
            try tap.start { [weak self] buffer, timestamp in
                self?.handleSystem(buffer, timestamp: timestamp)
            }
        } catch {
            systemAudioError = error
        }
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
            self?.restartMic(recreateFile: true)
        }
        inputDeviceChangeListener = inputBlock
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &inputAddress, DispatchQueue.main, inputBlock)
    }

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
        mic.stop()
        if recreateFile {
            micFile = nil
            micPadSeconds =
                AVAudioTime.seconds(forHostTime: mach_absolute_time()) - sessionStartHostSeconds
        }
        mic = MicRecorder()
        try? mic.start(echoCancellation: false) { [weak self] buffer in
            self?.handleMic(buffer)
        }
    }

    func stop() {
        removeDeviceChangeListener()
        mic.stop()
        tap.stop()
        micContinuation.finish()
        systemContinuation.finish()
        micFile = nil
        systemFile = nil
    }

    private func handleMic(_ buffer: AVAudioPCMBuffer) {
        let count = micBuffers.withLock { count in
            count += 1
            return count
        }
        if count == 1 {
            Self.log.info("first mic buffer: \(buffer.format.sampleRate)Hz")
        }
        if micFile == nil {
            micFile = try? AVAudioFile(
                forWriting: micURL,
                settings: Self.aacSettings(for: buffer.format, bitRate: 96_000),
                commonFormat: buffer.format.commonFormat,
                interleaved: buffer.format.isInterleaved)
            if let file = micFile, micPadSeconds > 0 {
                appendSilence(to: file, seconds: micPadSeconds, format: buffer.format)
            }
            micPadSeconds = 0
        }
        try? micFile?.write(from: buffer)
        let level = buffer.rmsLevel
        if level > 0.0005 {
            micNonSilent.withLock { $0 += 1 }
        }
        onLevel(.mic, level)
        if let copy = buffer.deepCopy() {
            micContinuation.yield(AudioChunk(buffer: copy, startSeconds: nil))
        }
    }

    private func appendSilence(to file: AVAudioFile, seconds: Double, format: AVAudioFormat) {
        var remaining = AVAudioFramePosition((seconds * format.sampleRate).rounded())
        while remaining > 0 {
            let chunkFrames = AVAudioFrameCount(min(remaining, 16_384))
            guard let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames)
            else { break }
            silence.frameLength = chunkFrames
            try? file.write(from: silence)
            remaining -= AVAudioFramePosition(chunkFrames)
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
        let sampleRate = buffer.format.sampleRate
        if systemFile == nil {
            systemFile = try? AVAudioFile(
                forWriting: systemURL,
                settings: Self.aacSettings(for: buffer.format, bitRate: 128_000),
                commonFormat: buffer.format.commonFormat,
                interleaved: buffer.format.isInterleaved)
        }

        var startSeconds: Double?
        if timestamp.mFlags.contains(.hostTimeValid) {
            startSeconds =
                AVAudioTime.seconds(forHostTime: timestamp.mHostTime) - sessionStartHostSeconds
        }

        // The tap only delivers buffers while system audio is playing. Pad gaps
        // with silence so file time stays equal to meeting time (transcript and
        // diarization timestamps must line up across channels).
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
        let level = buffer.rmsLevel
        if level > 0.0005 {
            systemNonSilent.withLock { $0 += 1 }
        }
        onLevel(.system, level)
        if let copy = buffer.deepCopy() {
            systemContinuation.yield(AudioChunk(buffer: copy, startSeconds: startSeconds))
        }
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
