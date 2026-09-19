import AVFoundation
import Foundation
import Speech
import Synchronization
import os

/// One SpeechAnalyzer at a time, after Record has stopped. Live analyzers
/// during capture were freezing the UI at ~125% CPU.
enum FileMeetingTranscriber {
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "transcription")
    private static let probeDurationSeconds = 15.0
    private static let probeFramesPerChunk: AVAudioFrameCount = 4_096

    /// The two external failure sources that used to be swallowed into a
    /// silent Void return: on-device model installation and per-channel file
    /// analysis. Tests inject fakes here to drive the typed outcome.
    struct Boundary: Sendable {
        var installModel: @Sendable (Locale) async throws -> Void
        var analyzeChannel: @Sendable (ChannelAnalysis) async throws -> Void

        static let live = Boundary(
            installModel: { locale in try await SpeechModels.ensureInstalled(locale: locale) },
            analyzeChannel: { try await analyzeToDatabase($0) })
    }

    struct ChannelAnalysis: Sendable {
        let url: URL
        let channel: AudioChannel
        let locale: Locale
        let meetingID: String
        let database: AppDatabase
    }

    /// Distinguishes "ran fine; the transcript may legitimately be empty for
    /// a silent meeting" from "failed; whatever segments exist are partial".
    enum Outcome: Sendable, Equatable {
        case completed(localeID: String)
        case failed(Failure)
    }

    enum Failure: Sendable, Equatable {
        /// ensureInstalled threw before any audio ran.
        case modelInstall(localeID: String)
        /// One or both channel analyzers threw; channels are in mic→system order.
        case channels([AudioChannel], localeID: String)

        /// Diagnostics for the local log only — the UI toast stays generic.
        var logDescription: String {
            switch self {
            case .modelInstall(let localeID):
                return "speech model installation failed (locale \(localeID))"
            case .channels(let channels, let localeID):
                return "channel analysis failed for [\(channels.map(\.rawValue).joined(separator: ", "))] (locale \(localeID))"
            }
        }
    }

    static func transcribe(
        micURL: URL,
        systemURL: URL,
        meetingID: String,
        language: String,
        database: AppDatabase,
        boundary: Boundary = .live
    ) async -> Outcome {
        let localeIDs = LanguageDetection.fileProbeLocales(
            requested: language,
            last: UserDefaults.standard.string(forKey: "lastSpeechLocale"))
        // Unreachable with LanguageDetection's non-empty defaults; keep the
        // old silent no-op rather than inventing an install error.
        guard let fallbackLocaleID = localeIDs.first else { return .completed(localeID: language) }
        let localeID = await selectLocaleID(
            candidates: localeIDs,
            fallback: fallbackLocaleID,
            micURL: micURL,
            installModel: boundary.installModel)
        let locale = Locale(identifier: localeID)
        do {
            try await boundary.installModel(locale)
        } catch {
            log.error(
                "model installation failed for locale \(localeID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return .failed(.modelInstall(localeID: localeID))
        }
        var failedChannels: [AudioChannel] = []
        for (url, channel) in [(micURL, AudioChannel.mic), (systemURL, AudioChannel.system)] {
            guard hasAudioToTranscribe(at: url) else { continue }
            do {
                try await boundary.analyzeChannel(
                    ChannelAnalysis(
                        url: url, channel: channel, locale: locale,
                        meetingID: meetingID, database: database))
            } catch {
                log.error(
                    "\(channel.rawValue, privacy: .public) channel analysis failed for meeting \(meetingID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                failedChannels.append(channel)
            }
        }
        // The locale was picked from real audio, so the hint stays durable
        // even when channel analysis failed. A model-install failure returns
        // above, before any audio ran, and leaves the previous hint intact.
        UserDefaults.standard.set(localeID, forKey: "lastSpeechLocale")
        guard failedChannels.isEmpty else {
            return .failed(.channels(failedChannels, localeID: localeID))
        }
        return .completed(localeID: localeID)
    }

    /// A missing or near-empty file means "no audio to transcribe", not a
    /// failure — that distinction is what keeps a silent meeting (full-length
    /// files, zero segments) from being reported as an error.
    private static func hasAudioToTranscribe(at url: URL) -> Bool {
        let path = url.path
        guard FileManager.default.isReadableFile(atPath: path) else { return false }
        let size =
            (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
            .int64Value ?? 0
        return size > 2048
    }

    private static func selectLocaleID(
        candidates: [String], fallback: String, micURL: URL,
        installModel: @Sendable (Locale) async throws -> Void
    ) async -> String {
        guard candidates.count > 1,
            let chunks = try? probeChunks(from: micURL),
            !chunks.isEmpty
        else { return fallback }

        var results: [LanguageProbeResult] = []
        for localeID in candidates {
            let locale = Locale(identifier: localeID)
            do {
                try await installModel(locale)
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

    /// Live per-channel analysis: open the recording, run the SpeechAnalyzer,
    /// persist final segments. Throws on any analyzer error so the caller can
    /// report it; a zero-length file is simply "no audio", not an error.
    private static func analyzeToDatabase(_ analysis: ChannelAnalysis) async throws {
        let file = try AVAudioFile(forReading: analysis.url)
        guard file.length > 0 else { return }
        let transcriber = SpeechTranscriber(
            locale: analysis.locale,
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
                    meetingID: analysis.meetingID,
                    channel: analysis.channel,
                    speaker: analysis.channel == .mic ? "Me" : "Them",
                    text: text,
                    startSeconds: start.isFinite ? start : 0,
                    endSeconds: end.isFinite ? end : (start.isFinite ? start : 0),
                    isFinal: true)
                try? analysis.database.save(segment)
            }
        }
        // Every exit path must wind the analyzer down (finalize or cancel) and
        // join the results pump. A stranded task or lingering analyzer —
        // modelRetention is .lingering — would bleed into the next channel's
        // analysis. The SpeechAnalyzer itself is a framework boundary: these
        // calls run against the real SDK, with no deterministic fake, which is
        // why the failure contract is tested through Boundary.analyzeChannel.
        var analyzerFinished = false
        do {
            // analyzeSequence returns the last sample time it analyzed, or
            // nil when no audio ran. Finalize through it when present; with
            // nil there is nothing to finalize, so cancelAndFinishNow winds
            // the analyzer down instead.
            let lastSampleTime = try await analyzer.analyzeSequence(from: file)
            if let lastSampleTime {
                try await analyzer.finalizeAndFinish(through: lastSampleTime)
            } else {
                await analyzer.cancelAndFinishNow()
            }
            analyzerFinished = true
            // A throw here means the results stream itself broke mid-meeting;
            // surfacing it marks the channel failed instead of silently
            // keeping whatever finals the pump already persisted.
            try await resultsTask.value
        } catch {
            if !analyzerFinished {
                await analyzer.cancelAndFinishNow()
            }
            resultsTask.cancel()
            // Join the pump before returning so a thrown channel can't carry
            // it into the next channel's analysis; its error is already
            // represented by the rethrow.
            _ = try? await resultsTask.value
            throw error
        }
    }
}
