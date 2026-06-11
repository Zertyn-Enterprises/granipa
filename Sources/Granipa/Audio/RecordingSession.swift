import AVFoundation
import CoreAudio
import Synchronization

// Mutable state is queue-confined: mic* fields are touched only from the mic tap
// callback thread, system* fields only from the tap IO queue. start/stop run on
// the main actor after callbacks have ceased.
final class RecordingSession: @unchecked Sendable {
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
    private let systemBuffers = Mutex(0)
    private let systemNonSilent = Mutex(0)
    private let onLevel: @Sendable (AudioChannel, Float) -> Void

    private var micFile: AVAudioFile?
    private var systemFile: AVAudioFile?
    private var systemFramesWritten: AVAudioFramePosition = 0
    private var sessionStartHostSeconds: Double = 0
    private(set) var systemAudioError: Error?
    private var deviceChangeListener: AudioObjectPropertyListenerBlock?

    var micBufferCount: Int { micBuffers.withLock { $0 } }
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
    }

    private func removeDeviceChangeListener() {
        guard let block = deviceChangeListener else { return }
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectRemovePropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        deviceChangeListener = nil
    }

    // A tap created before the system-audio TCC grant never delivers buffers;
    // tearing it down and recreating it picks the grant up without touching the
    // mic. Timing stays correct: gaps are padded with silence on the next buffer.
    func restartSystemTap() {
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

    // Recovery for the two observed zero-buffer cases: voice processing producing
    // no callbacks on some setups, and an engine started before the mic TCC grant.
    func restartMicWithoutEchoCancellation() {
        mic.stop()
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
        micBuffers.withLock { $0 += 1 }
        if micFile == nil {
            micFile = try? AVAudioFile(
                forWriting: micURL,
                settings: Self.aacSettings(for: buffer.format, bitRate: 96_000),
                commonFormat: buffer.format.commonFormat,
                interleaved: buffer.format.isInterleaved)
        }
        try? micFile?.write(from: buffer)
        onLevel(.mic, buffer.rmsLevel)
        if let copy = buffer.deepCopy() {
            micContinuation.yield(AudioChunk(buffer: copy, startSeconds: nil))
        }
    }

    private func handleSystem(_ buffer: AVAudioPCMBuffer, timestamp: AudioTimeStamp) {
        systemBuffers.withLock { $0 += 1 }
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
