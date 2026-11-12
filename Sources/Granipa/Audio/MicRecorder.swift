import AVFoundation
import os

final class MicRecorder {
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "mic")
    private let engine = AVAudioEngine()
    private var hasTap = false
    private var configurationObserver: NSObjectProtocol?

    /// `onConfigurationChange` fires when the engine stopped itself because the
    /// input hardware's sample rate or channel count changed.
    func start(
        echoCancellation: Bool,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void,
        onConfigurationChange: (@Sendable () -> Void)? = nil
    ) throws {
        let input = engine.inputNode
        if echoCancellation {
            try? input.setVoiceProcessingEnabled(true)
            // Voice processing ducks ALL other system audio by default — users
            // hear their meeting go quiet while we record. Minimize it.
            input.voiceProcessingOtherAudioDuckingConfiguration =
                AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                    enableAdvancedDucking: false, duckingLevel: .min)
        }
        let format = input.outputFormat(forBus: 0)
        Self.log.info(
            "mic start: aec=\(echoCancellation) format=\(format.sampleRate, privacy: .public)Hz ch=\(format.channelCount)")
        guard format.sampleRate > 0 else {
            Self.log.error("mic input format has zero sample rate - input device not ready")
            throw NSError(
                domain: "Granipa", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Microphone input device is not ready."])
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
            onBuffer(buffer, time)
        }
        hasTap = true
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            hasTap = false
            throw error
        }
        Self.log.info("mic engine running")
        if let onConfigurationChange {
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
            ) { _ in
                Self.log.info("mic engine configuration changed")
                onConfigurationChange()
            }
        }
    }

    func stop() {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
            self.configurationObserver = nil
        }
        if hasTap {
            engine.inputNode.removeTap(onBus: 0)
            hasTap = false
        }
        engine.stop()
    }
}
