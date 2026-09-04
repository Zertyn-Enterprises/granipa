import AVFoundation
import Foundation
import Speech
import Synchronization

/// One SpeechAnalyzer at a time, after Record has stopped. Live analyzers
/// during capture were freezing the UI at ~125% CPU.
enum FileMeetingTranscriber {
    private static let probeDurationSeconds = 15.0
    private static let probeFramesPerChunk: AVAudioFrameCount = 4_096

    static func transcribe(
        micURL: URL,
        systemURL: URL,
        meetingID: String,
        language: String,
        database: AppDatabase
    ) async {
        let localeIDs = LanguageDetection.fileProbeLocales(
            requested: language,
            last: UserDefaults.standard.string(forKey: "lastSpeechLocale"))
        guard let fallbackLocaleID = localeIDs.first else { return }
        let localeID = await selectLocaleID(
            candidates: localeIDs,
            fallback: fallbackLocaleID,
            micURL: micURL)
        let locale = Locale(identifier: localeID)
        do {
            try await SpeechModels.ensureInstalled(locale: locale)
        } catch {
            return
        }
        await transcribeFile(
            url: micURL, channel: .mic, locale: locale, meetingID: meetingID,
            database: database)
        await transcribeFile(
            url: systemURL, channel: .system, locale: locale, meetingID: meetingID,
            database: database)
        UserDefaults.standard.set(localeID, forKey: "lastSpeechLocale")
    }

    private static func selectLocaleID(
        candidates: [String], fallback: String, micURL: URL
    ) async -> String {
        guard candidates.count > 1,
            let chunks = try? probeChunks(from: micURL),
            !chunks.isEmpty
        else { return fallback }

        var results: [LanguageProbeResult] = []
        for localeID in candidates {
            let locale = Locale(identifier: localeID)
            do {
                try await SpeechModels.ensureInstalled(locale: locale)
                results.append(try await probe(localeID: localeID, chunks: chunks))
            } catch {
                continue
            }
        }
        return LanguageDetection.decide(results, force: true) ?? fallback
    }

    private static func probe(localeID: String, chunks: [AudioChunk]) async throws
        -> LanguageProbeResult
    {
        let accumulator = Mutex(LocaleProbe())
        let stream = AsyncStream<AudioChunk> { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
        try await transcribeChannel(
            channel: .mic,
            locale: Locale(identifier: localeID),
            chunks: stream
        ) { update in
            accumulator.withLock {
                $0.register(
                    text: update.text,
                    confidence: update.confidence,
                    isFinal: update.isFinal)
            }
        }
        return accumulator.withLock {
            LanguageProbeResult(
                localeID: localeID,
                text: $0.finalsText,
                confidence: $0.averageConfidence)
        }
    }

    private static func probeChunks(from url: URL) throws -> [AudioChunk] {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        let requestedFrames = AVAudioFramePosition(format.sampleRate * probeDurationSeconds)
        var remaining = min(file.length, requestedFrames)
        var chunks: [AudioChunk] = []

        while remaining > 0 {
            let frameCount = AVAudioFrameCount(
                min(remaining, AVAudioFramePosition(probeFramesPerChunk)))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                break
            }
            try file.read(into: buffer, frameCount: frameCount)
            guard buffer.frameLength > 0 else { break }
            chunks.append(AudioChunk(buffer: buffer, startSeconds: nil))
            remaining -= AVAudioFramePosition(buffer.frameLength)
        }
        return chunks
    }

    private static func transcribeFile(
        url: URL,
        channel: AudioChannel,
        locale: Locale,
        meetingID: String,
        database: AppDatabase
    ) async {
        let path = url.path
        guard FileManager.default.isReadableFile(atPath: path) else { return }
        let size =
            (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
            .int64Value ?? 0
        guard size > 2048 else { return }

        do {
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0 else { return }
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange, .transcriptionConfidence])
            let analyzer = SpeechAnalyzer(
                modules: [transcriber],
                options: SpeechAnalyzer.Options(
                    priority: .utility,
                    modelRetention: .lingering))
            let resultsTask = Task {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, result.isFinal else { continue }
                    let start = result.range.start.seconds
                    let end = result.range.end.seconds
                    let segment = TranscriptSegment.new(
                        meetingID: meetingID,
                        channel: channel,
                        speaker: channel == .mic ? "Me" : "Them",
                        text: text,
                        startSeconds: start.isFinite ? start : 0,
                        endSeconds: end.isFinite ? end : (start.isFinite ? start : 0),
                        isFinal: true)
                    try? database.save(segment)
                }
            }
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try? await resultsTask.value
        } catch {
            return
        }
    }
}
