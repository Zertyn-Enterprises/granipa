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
    private(set) var systemUsedMuse = false
    private(set) var systemWarning: String?

    let meetingID: String
    private let requestedLanguage: String
    private let database: AppDatabase
    private let micChunks: AsyncStream<AudioChunk>
    private let systemChunks: AsyncStream<AudioChunk>
    @ObservationIgnored private var channelTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var probeContinuations: [String: [AsyncStream<AudioChunk>.Continuation]] = [:]
    @ObservationIgnored private var probes: [String: LocaleProbe] = [:]
    @ObservationIgnored private var probeVolatiles: [String: String] = [:]
    @ObservationIgnored private var pendingFinals: [String: [TranscriptSegment]] = [:]
    @ObservationIgnored private var probeLocales: [String] = []
    @ObservationIgnored private var failedProbes: Set<String> = []
    @ObservationIgnored private var systemSpeechText = ""
    @ObservationIgnored private let micFan = ChunkFan()
    @ObservationIgnored private let systemFan = ChunkFan()
    @ObservationIgnored private var pumpsStarted = false
    @ObservationIgnored private let volatileMailbox = VolatileMailbox()
    @ObservationIgnored private var volatileFlush: Task<Void, Never>?
    @ObservationIgnored private var systemASRStarted = false
    @ObservationIgnored private var pendingSystemStreams: [String: AsyncStream<AudioChunk>] = [:]

    private var isAuto: Bool { requestedLanguage == "auto" }
    private var effectiveLocale: String? { isAuto ? detectedLocale : requestedLanguage }

    init(meetingID: String, language: String, session: RecordingSession, database: AppDatabase) {
        self.meetingID = meetingID
        self.requestedLanguage = language
        self.database = database
        self.micChunks = session.micChunks
        self.systemChunks = session.systemChunks
    }

    func start(adoptedLocale: String? = nil) {
        let locales: [String]
        if let adoptedLocale {
            locales = [adoptedLocale]
        } else {
            locales = LanguageDetection.startLocales(
                requested: requestedLanguage,
                last: UserDefaults.standard.string(forKey: "lastSpeechLocale"))
        }
        probeLocales = locales
        let task = Task {
            do {
                // Model install and SpeechTranscriber setup must not run on the
                // main actor — otherwise Record freezes the UI (Not Responding).
                try await Task.detached {
                    for localeID in locales {
                        try await SpeechModels.ensureInstalled(
                            locale: Locale(identifier: localeID))
                    }
                }.value
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            phase = .live
            startPumpsIfNeeded()
            startVolatileFlushLoop()
            if let adoptedLocale {
                // Re-prime a locale a previous attempt had already decided on,
                // so relaunched channels filter through the decided path.
                adopt(locale: adoptedLocale)
            } else if isAuto, locales.count == 1 {
                adopt(locale: locales[0])
            }
            startLiveChannels(locales: locales)
        }
        channelTasks.append(task)
    }

    /// Relaunch a failed attempt (model download, unsupported locale, dead
    /// probes). The channel pumps survive across attempts and the fan hands
    /// out fresh consumer streams, so the single-consumer session streams are
    /// never subscribed twice.
    func retryIfFailed() {
        guard case .failed = phase else { return }
        let adopted = detectedLocale
        detectedLocale = nil
        failedProbes = []
        probes = [:]
        probeVolatiles = [:]
        pendingFinals = [:]
        systemASRStarted = false
        finishAllProbes()
        phase = .preparing
        start(adoptedLocale: adopted)
    }

    /// The session streams are single-consumer and die with their first
    /// subscriber, so a persistent pump per channel feeds a fan that hands
    /// out fresh streams to each attempt's transcribers.
    private func startPumpsIfNeeded() {
        guard !pumpsStarted else { return }
        pumpsStarted = true
        let micFan = self.micFan
        let systemFan = self.systemFan
        channelTasks.append(Task.detached {
            for await chunk in self.micChunks {
                micFan.yield(chunk)
            }
            micFan.finish()
        })
        channelTasks.append(Task.detached {
            for await chunk in self.systemChunks {
                systemFan.yield(chunk)
            }
            systemFan.finish()
        })
    }

    func finishAndWait() async {
        if phase == .live || phase == .preparing {
            phase = .finishing
        }
        volatileFlush?.cancel()
        volatileFlush = nil
        volatileMailbox.reset()
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

    /// Mic analyzer first. The system analyzer waits until the mic model is
    /// loaded — two prepareToAnalyze at Record pegged the CPU and froze the UI.
    private func startLiveChannels(locales: [String]) {
        let micStreams = subscribe(.mic, locales: locales)
        if !MeetingASRPolicy.usesMuseForSystem() {
            pendingSystemStreams = subscribe(.system, locales: locales)
        }
        let systemOnce = OnceFlag { [weak self] in
            Task { @MainActor in
                self?.launchSystem(locales: locales)
            }
        }
        for localeID in locales {
            launch(
                channel: .mic,
                localeID: localeID,
                chunks: micStreams[localeID]!,
                onReady: { systemOnce.fire() })
        }
    }

    private func launchSystem(locales: [String]) {
        guard !systemASRStarted else { return }
        systemASRStarted = true
        if MeetingASRPolicy.usesMuseForSystem() {
            systemUsedMuse = true
            startMuseSystem()
            return
        }
        let streams = pendingSystemStreams
        pendingSystemStreams = [:]
        for localeID in locales {
            if let stream = streams[localeID] {
                launch(channel: .system, localeID: localeID, chunks: stream)
            }
        }
    }

    private func subscribe(_ channel: AudioChannel, locales: [String]) -> [String: AsyncStream<
        AudioChunk
    >] {
        var streams: [String: AsyncStream<AudioChunk>] = [:]
        for localeID in locales {
            let (stream, continuation) = fan(for: channel).subscribe()
            streams[localeID] = stream
            probeContinuations[localeID, default: []].append(continuation)
        }
        return streams
    }

    private func startChannel(_ channel: AudioChannel, locales: [String]) {
        let streams = subscribe(channel, locales: locales)
        for localeID in locales {
            launch(channel: channel, localeID: localeID, chunks: streams[localeID]!)
        }
    }

    private func startVolatileFlushLoop() {
        volatileFlush?.cancel()
        let mailbox = volatileMailbox
        volatileFlush = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(80))
                guard let self, !Task.isCancelled else { return }
                if let snap = mailbox.snapshotIfDirty() {
                    volatileMic = snap.mic
                    volatileSystem = snap.system
                }
            }
        }
    }

    private func fan(for channel: AudioChannel) -> ChunkFan {
        channel == .mic ? micFan : systemFan
    }

    private func startMuseSystem() {
        let task = Task {
            guard let apiKey = KeychainStore.get(account: KeychainStore.museAPIKeyAccount) else {
                systemUsedMuse = false
                startChannel(.system, locales: probeLocales)
                return
            }
            let biasIDs: [String] = {
                if requestedLanguage == "auto" {
                    return LanguageDetection.parseProbeLocales(
                        UserDefaults.standard.string(forKey: "probeLocales"))
                }
                return [requestedLanguage]
            }()
            let keywords = MuseLanguages.keywords(
                from: UserDefaults.standard.string(forKey: "dictationKeywords") ?? "")
            do {
                // A fresh fan subscription per attempt: the Muse consumer owns
                // this stream, never the single-consumer session stream, so a
                // retry or fallback can always subscribe again.
                let stream = systemFan.subscribe().stream
                try await MuseSystemTranscriber.transcribe(
                    chunks: stream,
                    configuration: .init(
                        apiKey: apiKey,
                        languageBias: MuseLanguages.bias(forLocaleIDs: biasIDs),
                        keywords: keywords),
                    onUpdate: { update in
                        Task { @MainActor in
                            self.applySystem(update)
                        }
                    },
                    onStatus: { message in
                        Task { @MainActor in
                            self.systemWarning = message
                        }
                    })
            } catch let error as DictationError {
                // The transcriber only throws before it starts consuming its
                // fan stream, so the Apple fallback can always subscribe fresh.
                switch error {
                case .museConnect, .museFailed, .audioFormat:
                    systemUsedMuse = false
                    startChannel(.system, locales: probeLocales)
                case .micBusy, .empty, .cancelled:
                    break
                }
            } catch {
                // Post-consume failures are reported via onStatus; whatever
                // Muse transcribed before dying stays in the transcript.
                systemWarning = "Them transcription stopped unexpectedly."
            }
        }
        channelTasks.append(task)
    }

    private func launch(
        channel: AudioChannel,
        localeID: String,
        chunks: AsyncStream<AudioChunk>,
        onReady: (@Sendable () -> Void)? = nil
    ) {
        let mailbox = volatileMailbox
        // The mic analyzer prepares first. System audio starts only after that
        // model is ready, then remains gated until remote speech arrives.
        let gating = channel == .system ? SpeechGate() : nil
        let task = Task.detached(priority: .medium) { [weak self] in
            do {
                try await transcribeChannel(
                    channel: channel,
                    locale: Locale(identifier: localeID),
                    chunks: chunks,
                    onReady: onReady,
                    gating: gating
                ) { update in
                    if update.isFinal {
                        Task { @MainActor in
                            self?.apply(update)
                        }
                    } else {
                        mailbox.set(channel: update.channel, text: update.text)
                    }
                }
            } catch {
                onReady?()
                await MainActor.run {
                    self?.channelFailed(localeID: localeID, error: error)
                }
            }
        }
        channelTasks.append(task)
    }

    private func channelFailed(localeID: String, error: Error) {
        if isAuto, detectedLocale == nil {
            failedProbes.insert(localeID)
            let remaining = probeLocales.filter { !failedProbes.contains($0) }
            if remaining.count == 1 {
                adopt(locale: remaining[0])
            } else if remaining.isEmpty {
                phase = .failed(error.localizedDescription)
                finishAllProbes()
            }
        } else if effectiveLocale == nil || effectiveLocale == localeID {
            phase = .failed(error.localizedDescription)
            finishAllProbes()
        }
    }

    private func finishAllProbes() {
        for (_, continuations) in probeContinuations {
            for continuation in continuations {
                continuation.finish()
            }
        }
        probeContinuations = [:]
        pendingSystemStreams = [:]
    }

    /// Muse system channel: locale-independent, so finals feed the language
    /// decision as a hint (the audio is the same the mic probes are guessing
    /// at) and then go straight to the decided path.
    private func applySystem(_ update: LiveTranscriptionUpdate) {
        if update.isFinal, isAuto, detectedLocale == nil {
            systemSpeechText += " " + update.text
            if systemSpeechText.count > 400 {
                systemSpeechText = String(systemSpeechText.suffix(400))
            }
            decideIfNeeded(force: false)
        }
        applyDecided(update)
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
            volatileMailbox.set(channel: update.channel, text: "")
        } else {
            volatileMailbox.set(channel: update.channel, text: update.text)
        }
    }

    private func segment(from update: LiveTranscriptionUpdate) -> TranscriptSegment {
        TranscriptSegment.new(
            meetingID: meetingID,
            channel: update.channel,
            speaker: update.speaker ?? (update.channel == .mic ? "Me" : "Them"),
            text: update.text,
            startSeconds: update.startSeconds ?? 0,
            endSeconds: update.endSeconds ?? update.startSeconds ?? 0,
            isFinal: true)
    }

    /// Mic finals join whatever system finals (Muse) were already saved and
    /// visible, on one meeting-relative timeline.
    nonisolated static func mergedLiveSegments(
        micFinals: [TranscriptSegment], existing: [TranscriptSegment]
    ) -> [TranscriptSegment] {
        (micFinals + existing.filter { $0.channel == .system })
            .sorted { $0.startSeconds < $1.startSeconds }
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
        volatileMailbox.set(channel: .mic, text: probeVolatiles["\(leader)|mic"] ?? "")
        volatileMailbox.set(channel: .system, text: probeVolatiles["\(leader)|system"] ?? "")
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
        guard
            let winner = LanguageDetection.decide(
                candidates, force: force,
                systemHint: systemSpeechText.isEmpty ? nil : systemSpeechText)
        else { return }
        adopt(locale: winner)
    }

    func adopt(locale: String) {
        guard detectedLocale == nil else { return }
        detectedLocale = locale
        UserDefaults.standard.set(locale, forKey: "lastSpeechLocale")

        let finals = (pendingFinals[locale] ?? []).sorted { $0.startSeconds < $1.startSeconds }
        for segment in finals {
            try? database.save(segment)
        }
        // System finals (Muse) may already be saved and visible while the mic
        // probes were still deciding; keep them in the live timeline.
        liveSegments = Self.mergedLiveSegments(micFinals: finals, existing: liveSegments)
        pendingFinals = [:]
        probes = [:]
        probeVolatiles = [:]
        volatileMailbox.reset()
        volatileMic = ""
        volatileSystem = ""
        systemSpeechText = ""

        for (localeID, continuations) in probeContinuations where localeID != locale {
            for continuation in continuations {
                continuation.finish()
            }
        }
        probeContinuations = probeContinuations.filter { $0.key == locale }

        if var meeting = try? database.fetchMeeting(id: meetingID), meeting.language != locale {
            meeting.language = locale
            try? database.save(meeting)
        }
    }
}

/// Re-subscribable fan-out between the single-consumer session streams and
/// per-attempt consumers. Dead consumers (finished or abandoned) drop off
/// via `onTermination` so yield does not buffer PCM into an unread stream.
final class ChunkFan: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<AudioChunk>.Continuation] = [:]

    var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }

    func subscribe() -> (stream: AsyncStream<AudioChunk>, continuation: AsyncStream<AudioChunk>.Continuation) {
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self)
        lock.lock()
        continuations[id] = continuation
        lock.unlock()
        continuation.onTermination = { [weak self] _ in
            self?.remove(id)
        }
        return (stream, continuation)
    }

    func yield(_ chunk: AudioChunk) {
        lock.lock()
        let list = Array(continuations.values)
        lock.unlock()
        for continuation in list {
            continuation.yield(chunk)
        }
    }

    func finish() {
        lock.lock()
        let list = Array(continuations.values)
        continuations = [:]
        lock.unlock()
        for continuation in list {
            continuation.finish()
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        continuations[id] = nil
        lock.unlock()
    }
}

/// Off-main volatile text. Speech results must not hop to the main actor
/// per hypothesis — that flood froze Record even after coalescing publishes.
final class VolatileMailbox: @unchecked Sendable {
    private let lock = NSLock()
    private var mic = ""
    private var system = ""
    private var dirty = false

    func set(channel: AudioChannel, text: String) {
        lock.lock()
        switch channel {
        case .mic: mic = text
        case .system: system = text
        }
        dirty = true
        lock.unlock()
    }

    func snapshotIfDirty() -> (mic: String, system: String)? {
        lock.lock()
        defer { lock.unlock() }
        guard dirty else { return nil }
        dirty = false
        return (mic, system)
    }

    func reset() {
        lock.lock()
        mic = ""
        system = ""
        dirty = false
        lock.unlock()
    }
}

final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    private let action: @Sendable () -> Void

    init(action: @escaping @Sendable () -> Void) {
        self.action = action
    }

    func fire() {
        lock.lock()
        let shouldRun = !fired
        fired = true
        lock.unlock()
        if shouldRun { action() }
    }
}
