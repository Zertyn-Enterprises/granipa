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
    /// How far into a file the probe looks for speech before giving up on it.
    private static let probeSearchSeconds = 300.0
    private static let probeFramesPerChunk: AVAudioFrameCount = 4_096

    /// The two external failure sources that used to be swallowed into a
    /// silent Void return: on-device model installation and per-channel file
    /// analysis (which returns the channel's final segments). Tests inject
    /// fakes here to drive the typed outcome.
    struct Boundary: Sendable {
        var installModel: @Sendable (Locale) async throws -> Void
        var analyzeChannel: @Sendable (ChannelAnalysis) async throws -> [TranscriptSegment]
        var isInstalled: @Sendable (Locale) async -> Bool = { _ in true }

        static let live = Boundary(
            installModel: { locale in try await SpeechModels.ensureInstalled(locale: locale) },
            analyzeChannel: { try await analyze($0) },
            isInstalled: { await SpeechModels.isInstalled(locale: $0) })
    }

    /// The locale a meeting is transcribed with; `probed` when a probe of real
    /// speech chose it rather than the fallback.
    struct LocaleChoice: Equatable {
        let localeID: String
        let probed: Bool
    }

    struct ChannelAnalysis: Sendable {
        let url: URL
        let channel: AudioChannel
        let locale: Locale
        let meetingID: String
    }

    /// Distinguishes "ran fine; the transcript may legitimately be empty for
    /// a silent meeting" from "failed; a failed channel kept its previous
    /// segments".
    enum Outcome: Sendable, Equatable {
        case completed(localeID: String)
        case failed(Failure)
    }

    struct Transcription: Sendable, Equatable {
        let outcome: Outcome
        /// The meeting's language once known for sure (a probe of speech
        /// decided, or there was one candidate); the caller saves it.
        let language: String?
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
        onChannel: @Sendable (AudioChannel) async -> Void = { _ in },
        boundary: Boundary = .live
    ) async -> Transcription {
        let localeIDs = LanguageDetection.fileProbeLocales(
            requested: language,
            last: UserDefaults.standard.string(forKey: "lastSpeechLocale"))
        // Unreachable with LanguageDetection's non-empty defaults; keep the
        // old silent no-op rather than inventing an install error.
        guard !localeIDs.isEmpty else {
            return Transcription(outcome: .completed(localeID: language), language: nil)
        }
        let choice = await chooseLocale(
            candidates: localeIDs, micURL: micURL, systemURL: systemURL, boundary: boundary)
        let localeID = choice.localeID
        let locale = Locale(identifier: localeID)
        do {
            try await boundary.installModel(locale)
        } catch {
            log.error(
                "model installation failed for locale \(localeID, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
            return Transcription(outcome: .failed(.modelInstall(localeID: localeID)), language: nil)
        }
        var failedChannels: [AudioChannel] = []
        // A channel's previous segments are swapped for the new ones in one
        // transaction, and only once its analysis succeeded: a channel with no
        // audio or a failed analysis keeps the transcript it had.
        for (url, channel) in [(micURL, AudioChannel.mic), (systemURL, AudioChannel.system)] {
            guard hasAudioToTranscribe(at: url) else { continue }
            await onChannel(channel)
            do {
                let segments = try await boundary.analyzeChannel(
                    ChannelAnalysis(url: url, channel: channel, locale: locale, meetingID: meetingID))
                try database.replaceSegments(meetingID: meetingID, channel: channel, with: segments)
            } catch {
                log.error(
                    "\(channel.rawValue, privacy: .public) channel analysis failed for meeting \(meetingID, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
                failedChannels.append(channel)
            }
        }
        // Only a probe of real speech may steer the next meeting's guess, even
        // when channel analysis failed. A model-install failure returns above
        // and leaves the previous hint intact.
        if choice.probed {
            UserDefaults.standard.set(localeID, forKey: "lastSpeechLocale")
        }
        let known = choice.probed || localeIDs.count == 1 ? localeID : nil
        guard failedChannels.isEmpty else {
            return Transcription(
                outcome: .failed(.channels(failedChannels, localeID: localeID)), language: known)
        }
        return Transcription(outcome: .completed(localeID: localeID), language: known)
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

    private static func chooseLocale(
        candidates: [String], micURL: URL, systemURL: URL, boundary: Boundary
    ) async -> LocaleChoice {
        let fallback = LocaleChoice(localeID: candidates[0], probed: false)
        var installed: Set<String> = []
        for localeID in candidates.dropFirst() {
            if await boundary.isInstalled(Locale(identifier: localeID)) {
                installed.insert(localeID)
            }
        }
        let probed = LanguageDetection.probeCandidates(candidates, installed: installed)
        guard probed.count > 1,
            let chunks = speechChunks(from: micURL) ?? speechChunks(from: systemURL)
        else { return fallback }

        var results: [LanguageProbeResult] = []
        for localeID in probed {
            do {
                try await boundary.installModel(Locale(identifier: localeID))
                results.append(try await probe(localeID: localeID, chunks: chunks))
            } catch {
                continue
            }
        }
        guard let decided = LanguageDetection.decide(results, force: true) else { return fallback }
        return LocaleChoice(localeID: decided, probed: true)
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

    /// Up to `probeDurationSeconds` of speech found in the first
    /// `probeSearchSeconds` of the file, or nil when it has none: leading
    /// silence, or a silent channel, would make every probe come back empty.
    private static func speechChunks(from url: URL) -> [AudioChunk]? {
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let format = file.processingFormat
        var gate = SpeechGate()
        var searchLeft = AVAudioFramePosition(format.sampleRate * probeSearchSeconds)
        var speechLeft = AVAudioFramePosition(format.sampleRate * probeDurationSeconds)
        var chunks: [AudioChunk] = []
        while searchLeft > 0, speechLeft > 0 {
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: format, frameCapacity: probeFramesPerChunk),
                (try? file.read(into: buffer, frameCount: probeFramesPerChunk)) != nil,
                buffer.frameLength > 0
            else { break }
            searchLeft -= AVAudioFramePosition(buffer.frameLength)
            let chunk = AudioChunk(buffer: buffer, startSeconds: nil)
            guard gate.admits(chunk) else { continue }
            chunks.append(chunk)
            speechLeft -= AVAudioFramePosition(buffer.frameLength)
        }
        return chunks.isEmpty ? nil : chunks
    }

    /// The channel's final results as segments.
    private static func collectFinals(
        of transcriber: SpeechTranscriber, _ analysis: ChannelAnalysis
    ) async throws -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
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
            segments.append(segment)
        }
        return segments
    }

    /// Live per-channel analysis: open the recording, run the SpeechAnalyzer,
    /// return its final segments. Throws on any analyzer error so the caller
    /// can report it; a zero-length file is simply "no audio", not an error.
    private static func analyze(_ analysis: ChannelAnalysis) async throws -> [TranscriptSegment] {
        let file = try AVAudioFile(forReading: analysis.url)
        guard file.length > 0 else { return [] }
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
        let resultsTask = Task { try await collectFinals(of: transcriber, analysis) }
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
            // surfacing it marks the channel failed instead of replacing its
            // transcript with a partial one.
            return try await resultsTask.value
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
