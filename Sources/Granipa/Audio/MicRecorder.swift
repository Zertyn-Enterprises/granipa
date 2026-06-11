import AVFoundation
import os

final class MicRecorder {
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "mic")
    private let engine = AVAudioEngine()

    func start(
        echoCancellation: Bool,
        onBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void
    ) throws {
        let input = engine.inputNode
        if echoCancellation {
            try? input.setVoiceProcessingEnabled(true)
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
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            onBuffer(buffer)
        }
        engine.prepare()
        try engine.start()
        Self.log.info("mic engine running")
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }
}
