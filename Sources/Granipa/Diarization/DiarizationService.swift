import Foundation
import os

#if canImport(FluidAudio)
import FluidAudio
#endif

enum DiarizationService {
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "diarization")

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
        else {
            log.info("skipped: no system audio file")
            return
        }

        #if canImport(FluidAudio)
        let allSegments = try database.fetchSegments(meetingID: meetingID, finalOnly: true)
        let systemSegments = allSegments.filter { $0.channel == .system }
        guard !systemSegments.isEmpty else {
            log.info("skipped: no system transcript segments")
            return
        }

        log.info("starting: \(systemSegments.count) system segments")
        let manager = OfflineDiarizerManager()
        try await manager.prepareModels()
        log.info("models ready, processing audio")
        let result = try await manager.process(URL(fileURLWithPath: path))
        let speakerIDs = Set(result.segments.map(\.speakerId))
        log.info("found \(result.segments.count) spans, \(speakerIDs.count) distinct speakers")

        let spans = result.segments.map {
            SpeakerSpan(
                speakerID: $0.speakerId,
                start: Double($0.startTimeSeconds),
                end: Double($0.endTimeSeconds))
        }
        var relabeled = SpeakerMapping.relabel(segments: systemSegments, spans: spans)

        if let providerID = nameInferenceProviderID {
            relabeled = await applyNames(
                providerID: providerID,
                systemSegments: relabeled,
                allSegments: allSegments)
        }

        let finalSpeakers = Set(relabeled.map(\.speaker))
        log.info("done: speakers now \(finalSpeakers.sorted().joined(separator: ", "), privacy: .public)")
        try database.replaceSegments(meetingID: meetingID, channel: .system, with: relabeled)
        #endif
    }

    /// Name Muse/local "Speaker A" labels without running FluidAudio again.
    static func inferNames(
        meetingID: String,
        database: AppDatabase,
        providerID: String
    ) async throws {
        let allSegments = try database.fetchSegments(meetingID: meetingID, finalOnly: true)
        let systemSegments = allSegments.filter { $0.channel == .system }
        guard !systemSegments.isEmpty else { return }
        let relabeled = await applyNames(
            providerID: providerID,
            systemSegments: systemSegments,
            allSegments: allSegments)
        try database.replaceSegments(meetingID: meetingID, channel: .system, with: relabeled)
    }

    private static func applyNames(
        providerID: String,
        systemSegments: [TranscriptSegment],
        allSegments: [TranscriptSegment]
    ) async -> [TranscriptSegment] {
        let labels = Set(systemSegments.map(\.speaker)).filter { $0.hasPrefix("Speaker ") }.sorted()
        guard !labels.isEmpty else { return systemSegments }
        let micSegments = allSegments.filter { $0.channel == .mic }
        let transcript = EnhancementService.transcriptText(segments: micSegments + systemSegments)
        let prompt = SpeakerMapping.nameInferencePrompt(
            transcript: transcript, speakerLabels: labels)
        guard let raw = try? await LLMService.generate(providerID: providerID, prompt: prompt)
        else { return systemSegments }
        let names = SpeakerMapping.parseNames(raw, speakerLabels: labels)
        log.info("name inference: \(names.count)/\(labels.count) labels named")
        return SpeakerMapping.applyNames(names, to: systemSegments)
    }
}
