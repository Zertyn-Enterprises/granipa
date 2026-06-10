import Foundation

#if canImport(FluidAudio)
import FluidAudio
#endif

enum DiarizationService {
    static var isAvailable: Bool {
        #if canImport(FluidAudio)
        return true
        #else
        return false
        #endif
    }

    static func diarize(
        meetingID: String,
        audioSystemPath: String?,
        database: AppDatabase,
        nameInferenceProviderID: String?
    ) async throws {
        guard
            let path = audioSystemPath,
            FileManager.default.fileExists(atPath: path)
        else { return }

        #if canImport(FluidAudio)
        let allSegments = try database.fetchSegments(meetingID: meetingID, finalOnly: true)
        let systemSegments = allSegments.filter { $0.channel == .system }
        guard !systemSegments.isEmpty else { return }

        let manager = OfflineDiarizerManager()
        try await manager.prepareModels()
        let result = try await manager.process(URL(fileURLWithPath: path))

        let spans = result.segments.map {
            SpeakerSpan(
                speakerID: $0.speakerId,
                start: Double($0.startTimeSeconds),
                end: Double($0.endTimeSeconds))
        }
        var relabeled = SpeakerMapping.relabel(segments: systemSegments, spans: spans)

        if let providerID = nameInferenceProviderID {
            let labels = Set(relabeled.map(\.speaker)).filter { $0.hasPrefix("Speaker ") }.sorted()
            if !labels.isEmpty {
                let micSegments = allSegments.filter { $0.channel == .mic }
                let transcript = EnhancementService.transcriptText(
                    segments: micSegments + relabeled)
                let prompt = SpeakerMapping.nameInferencePrompt(
                    transcript: transcript, speakerLabels: labels)
                if let raw = try? await LLMService.generate(providerID: providerID, prompt: prompt) {
                    let names = SpeakerMapping.parseNames(raw, speakerLabels: labels)
                    relabeled = SpeakerMapping.applyNames(names, to: relabeled)
                }
            }
        }

        try database.replaceSegments(meetingID: meetingID, channel: .system, with: relabeled)
        #endif
    }
}
