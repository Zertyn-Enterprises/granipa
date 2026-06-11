import Foundation
import Observation

@MainActor
@Observable
final class TranscriptionCoordinator {
    enum Phase: Equatable {
        case preparing
        case live
        case finishing
        case done
        case failed(String)
    }

    private(set) var phase: Phase = .preparing
    private(set) var volatileMic = ""
    private(set) var volatileSystem = ""
    private(set) var liveSegments: [TranscriptSegment] = []
    private(set) var detectedLocale: String?

    let meetingID: String
    private let requestedLanguage: String
    private let database: AppDatabase
    private let micChunks: AsyncStream<AudioChunk>
    private let systemChunks: AsyncStream<AudioChunk>
    private var channelTasks: [Task<Void, Never>] = []
    private var probeContinuations: [String: [AsyncStream<AudioChunk>.Continuation]] = [:]
    private var probes: [String: LocaleProbe] = [:]
    private var probeVolatiles: [String: String] = [:]
    private var pendingFinals: [String: [TranscriptSegment]] = [:]
    private var probeLocales: [String] = []
    private var failedProbes: Set<String> = []

    private var isAuto: Bool { requestedLanguage == "auto" }
    private var effectiveLocale: String? { isAuto ? detectedLocale : requestedLanguage }

    init(meetingID: String, language: String, session: RecordingSession, database: AppDatabase) {
        self.meetingID = meetingID
        self.requestedLanguage = language
        self.database = database
        self.micChunks = session.micChunks
        self.systemChunks = session.systemChunks
    }

    func start() {
        let locales =
            isAuto
            ? LanguageDetection.parseProbeLocales(
                UserDefaults.standard.string(forKey: "probeLocales"))
            : [requestedLanguage]
        probeLocales = locales
        let task = Task {
            do {
                for localeID in locales {
                    try await SpeechModels.ensureInstalled(locale: Locale(identifier: localeID))
                }
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            phase = .live
            if isAuto, locales.count == 1 {
                adopt(locale: locales[0])
            }
            startChannel(.mic, source: micChunks, locales: locales)
            startChannel(.system, source: systemChunks, locales: locales)
        }
        channelTasks.append(task)
    }

    func finishAndWait() async {
        if phase == .live || phase == .preparing {
            phase = .finishing
        }
        decideIfNeeded(force: true)
        // Channel tasks can be appended while we await (model install finishing
        // just as the meeting stops), so index instead of iterating a snapshot.
        var index = 0
        while index < channelTasks.count {
            await channelTasks[index].value
            index += 1
        }
        decideIfNeeded(force: true)
        volatileMic = ""
        volatileSystem = ""
        if case .failed = phase {} else {
            phase = .done
        }
    }

    private func startChannel(
        _ channel: AudioChannel, source: AsyncStream<AudioChunk>, locales: [String]
    ) {
        var continuations: [AsyncStream<AudioChunk>.Continuation] = []
        var streams: [String: AsyncStream<AudioChunk>] = [:]
        for localeID in locales {
            let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self)
            streams[localeID] = stream
            continuations.append(continuation)
            probeContinuations[localeID, default: []].append(continuation)
        }
        // Yielding to a finished continuation is a no-op, so the pump can stay
        // stateless: losers are shut down by finishing their continuations.
        let pump = Task.detached {
            for await chunk in source {
                for continuation in continuations {
                    continuation.yield(chunk)
                }
            }
            for continuation in continuations {
                continuation.finish()
            }
        }
        channelTasks.append(pump)

        for localeID in locales {
            launch(channel: channel, localeID: localeID, chunks: streams[localeID]!)
        }
    }

    private func launch(channel: AudioChannel, localeID: String, chunks: AsyncStream<AudioChunk>) {
        let task = Task {
            do {
                try await transcribeChannel(
                    channel: channel, locale: Locale(identifier: localeID), chunks: chunks
                ) { update in
                    Task { @MainActor in
                        self.apply(update)
                    }
                }
            } catch {
                if isAuto, detectedLocale == nil {
                    failedProbes.insert(localeID)
                    let remaining = probeLocales.filter { !failedProbes.contains($0) }
                    if remaining.count == 1 {
                        adopt(locale: remaining[0])
                    } else if remaining.isEmpty {
                        phase = .failed(error.localizedDescription)
                    }
                } else if effectiveLocale == nil || effectiveLocale == localeID {
                    phase = .failed(error.localizedDescription)
                }
            }
        }
        channelTasks.append(task)
    }

    private func apply(_ update: LiveTranscriptionUpdate) {
        if let locale = effectiveLocale {
            guard update.localeID == locale else { return }
            applyDecided(update)
            return
        }

        var probe = probes[update.localeID] ?? LocaleProbe()
        probe.register(text: update.text, confidence: update.confidence, isFinal: update.isFinal)
        probes[update.localeID] = probe

        if update.isFinal {
            probeVolatiles["\(update.localeID)|\(update.channel.rawValue)"] = ""
            pendingFinals[update.localeID, default: []].append(segment(from: update))
        } else {
            probeVolatiles["\(update.localeID)|\(update.channel.rawValue)"] = update.text
        }
        showProbeVolatiles()
        decideIfNeeded(force: false)
    }

    private func applyDecided(_ update: LiveTranscriptionUpdate) {
        if update.isFinal {
            switch update.channel {
            case .mic: volatileMic = ""
            case .system: volatileSystem = ""
            }
            let segment = segment(from: update)
            do {
                try database.save(segment)
            } catch {
                phase = .failed(error.localizedDescription)
            }
            liveSegments.append(segment)
            liveSegments.sort { $0.startSeconds < $1.startSeconds }
        } else {
            switch update.channel {
            case .mic: volatileMic = update.text
            case .system: volatileSystem = update.text
            }
        }
    }

    private func segment(from update: LiveTranscriptionUpdate) -> TranscriptSegment {
        TranscriptSegment.new(
            meetingID: meetingID,
            channel: update.channel,
            speaker: update.channel == .mic ? "Me" : "Them",
            text: update.text,
            startSeconds: update.startSeconds ?? 0,
            endSeconds: update.endSeconds ?? update.startSeconds ?? 0,
            isFinal: true)
    }

    private func probeText(_ localeID: String) -> String {
        let finals = probes[localeID]?.finalsText ?? ""
        let micVolatile = probeVolatiles["\(localeID)|mic"] ?? ""
        let systemVolatile = probeVolatiles["\(localeID)|system"] ?? ""
        return [finals, micVolatile, systemVolatile]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func showProbeVolatiles() {
        let active = probeLocales.filter { !failedProbes.contains($0) }
        let leader =
            active.max {
                (probes[$0]?.averageConfidence ?? 0) < (probes[$1]?.averageConfidence ?? 0)
            } ?? probeLocales.first ?? "en-US"
        volatileMic = probeVolatiles["\(leader)|mic"] ?? ""
        volatileSystem = probeVolatiles["\(leader)|system"] ?? ""
    }

    private func decideIfNeeded(force: Bool) {
        guard isAuto, detectedLocale == nil else { return }
        let candidates = probeLocales
            .filter { !failedProbes.contains($0) }
            .map {
                LanguageProbeResult(
                    localeID: $0,
                    text: probeText($0),
                    confidence: probes[$0]?.averageConfidence ?? 0)
            }
        guard let winner = LanguageDetection.decide(candidates, force: force) else { return }
        adopt(locale: winner)
    }

    private func adopt(locale: String) {
        guard detectedLocale == nil else { return }
        detectedLocale = locale

        let finals = (pendingFinals[locale] ?? []).sorted { $0.startSeconds < $1.startSeconds }
        for segment in finals {
            try? database.save(segment)
        }
        liveSegments = finals
        pendingFinals = [:]
        probes = [:]
        probeVolatiles = [:]
        volatileMic = ""
        volatileSystem = ""

        for (localeID, continuations) in probeContinuations where localeID != locale {
            for continuation in continuations {
                continuation.finish()
            }
        }

        if var meeting = try? database.fetchMeeting(id: meetingID), meeting.language != locale {
            meeting.language = locale
            try? database.save(meeting)
        }
    }
}
