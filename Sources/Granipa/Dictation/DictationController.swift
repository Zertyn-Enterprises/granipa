import AppKit
import AVFoundation
import Carbon.HIToolbox
import Foundation
import Observation
import os

@MainActor
@Observable
final class DictationController {
    static let shared = DictationController()

    private(set) var phase: DictationPhase = .idle
    private(set) var preview = ""
    nonisolated static let waveformBars = 40
    private(set) var waveform: [Float] = Array(repeating: 0, count: waveformBars)
    private(set) var engineID: DictationEngineID = .local
    private(set) var isToggle = false
    private(set) var isRewriting = false
    private(set) var lastFailureRetryable = false
    var meetingIsRecording = false
    var onCommitted: (@MainActor (String, TimeInterval, String?) -> Void)?

    private var pressStartedAt: Date?
    private var stoppedAt: Date?
    private var pasteTarget: pid_t?
    private var pressEventTimestamp: TimeInterval?
    private var sourceApp: String?
    private var sessionGeneration = 0
    private var captureGeneration = 0
    private var reachedListening = false
    private var chunkContinuation: AsyncStream<AudioChunk>.Continuation?
    private var transcribeTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var stallTask: Task<Void, Never>?
    private var mic: MicRecorder?
    private let appleEngine = AppleDictationEngine()
    private let museEngine = MuseDictationEngine()
    @ObservationIgnored private let waveformGate = LevelGate(minInterval: 0.08)
    /// Last mic buffer arrival. A device change (AirPods in/out) stops the
    /// engine without an error, so silence from the tap is the only signal.
    @ObservationIgnored private let micHeartbeat = OSAllocatedUnfairLock(
        initialState: ContinuousClock.now)
    #if DEBUG
        @ObservationIgnored var testHooks: DictationTestHooks?
    #endif

    private init() {}

    #if DEBUG
        init(testHooks: DictationTestHooks) {
            self.testHooks = testHooks
        }

        var testSessionGeneration: Int { sessionGeneration }

        func publishPreviewForTesting(_ text: String, generation: Int) {
            publishPreview(text, generation: generation)
        }
    #endif

    static var shortcutLabel: String {
        let keyCode = UserDefaults.standard.object(forKey: "dictationKeyCode") as? Int
            ?? Int(kVK_RightOption)
        let modifiers = UserDefaults.standard.object(forKey: "dictationModifiers") as? Int ?? 0
        if keyCode == Int(kVK_RightCommand) { return "Right ⌘" }
        if keyCode == Int(kVK_Space), modifiers == Int(optionKey) { return "⌥ Space" }
        return "Right ⌥"
    }

    func handlePress(at timestamp: TimeInterval) {
        switch phase {
        case .preparing:
            Task { await stop() }
        case .listening where isToggle:
            Task { await stop() }
        case .idle, .done, .failed:
            pressEventTimestamp = timestamp
            start(latched: false)
        default:
            break
        }
    }

    func handleRelease(at timestamp: TimeInterval) {
        guard phase == .listening || phase == .preparing, !isToggle else { return }
        guard let pressed = pressEventTimestamp else { return }
        switch DictationTrigger.actionOnRelease(press: pressed, release: timestamp) {
        case .keepAsToggle:
            isToggle = true
        case .stop:
            Task { await stop() }
        }
    }

    /// The held dictation modifier turned out to be part of a shortcut (Right ⌘+C):
    /// drop the session that press started instead of latching it open.
    func handleChord() {
        guard pressEventTimestamp != nil, !isToggle,
            phase == .preparing || phase == .listening
        else { return }
        cancel()
    }

    func toggleFromMenu() {
        if phase.isActive {
            Task { await stop() }
        } else {
            start(latched: true)
        }
    }

    func retry() {
        guard case .failed = phase, lastFailureRetryable else { return }
        start(latched: true)
    }

    func cancel() {
        let task = transcribeTask
        invalidateSession()
        task?.cancel()
        resetToIdle()
    }

    private func start(latched: Bool) {
        #if DEBUG
        if V2FixtureRuntime.isActive { return }
        #endif
        if meetingIsRecording {
            fail(DictationError.micBusy)
            return
        }
        let generation = beginSession(latched: latched)
        if presentsChrome {
            DictationOverlayController.shared.attach(self)
            DictationOverlayController.shared.setClickThrough(false)
            DictationOverlayController.shared.setVisible(true)
            CaptionsOverlayController.shared.setVisible(false)
            registerEscape()
        }
        transcribeTask = Task { [weak self] in
            await self?.runSession(generation: generation)
        }
    }

    /// Resets per-session state, enters `.preparing` and returns the new generation.
    private func beginSession(latched: Bool) -> Int {
        hideTask?.cancel()
        pressStartedAt = .now
        stoppedAt = nil
        if latched { pressEventTimestamp = nil }
        isToggle = latched
        isRewriting = false
        lastFailureRetryable = false
        preview = ""
        waveform = Array(repeating: 0, count: Self.waveformBars)
        engineID = DictationEngineID(
            rawValue: UserDefaults.standard.string(forKey: "dictationEngine") ?? "local")
            ?? .local
        sessionGeneration += 1
        let front = NSWorkspace.shared.frontmostApplication
        sourceApp =
            front?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? nil : front?.localizedName
        phase = .preparing
        reachedListening = false
        return sessionGeneration
    }

    private func runSession(generation: Int) async {
        do {
            guard let stream = try await openCapture(generation: generation) else { return }
            try await prepareEngine()
            guard !Task.isCancelled, generation == sessionGeneration else { return }
            let text = try await runEngine(chunks: stream, generation: generation)
            guard !Task.isCancelled, generation == sessionGeneration else { return }
            await finish(text: text)
        } catch is CancellationError {
            return
        } catch let error as DictationError where error.isCancelled {
            return
        } catch {
            guard generation == sessionGeneration else { return }
            fail(error)
        }
    }

    /// Opens the mic and enters `.listening`; nil when the session was
    /// cancelled or stopped before the capture was usable.
    private func openCapture(generation: Int) async throws -> AsyncStream<AudioChunk>? {
        #if DEBUG
            if let beforeCapture = testHooks?.beforeCapture {
                await beforeCapture()
            }
        #endif
        guard !Task.isCancelled, generation == sessionGeneration, phase == .preparing
        else { return nil }
        let stream = try beginCapture()
        guard !Task.isCancelled, generation == sessionGeneration else {
            if captureGeneration == generation { finishMic() }
            return nil
        }
        if phase == .preparing {
            phase = .listening
            reachedListening = true
            if presentsChrome {
                DictationOverlayController.shared.setClickThrough(false)
            }
            watchForMicStall(generation: generation)
        }
        guard phase == .listening || phase == .processing else {
            if captureGeneration == generation { finishMic() }
            return nil
        }
        return stream
    }

    private func prepareEngine() async throws {
        #if DEBUG
            if testHooks != nil {
                if let prepare = testHooks?.prepareEngine {
                    try await prepare()
                }
                return
            }
        #endif
        switch engineID {
        case .local:
            try await SpeechModels.ensureInstalled(locale: Self.preferredLocale())
        case .muse:
            guard KeychainStore.hasMuseKey() else {
                throw DictationError.museFailed(
                    "Add a Meta API key in Settings → Dictation to use Muse.")
            }
        }
    }

    var hasOpenCapture: Bool { chunkContinuation != nil || mic != nil }

    private var presentsChrome: Bool {
        #if DEBUG
            if testHooks != nil { return testHooks?.presentsOverlay == true }
        #endif
        return true
    }

    private var shouldPaste: Bool {
        #if DEBUG
            if testHooks != nil { return testHooks?.pastes == true }
        #endif
        return true
    }

    func beginCapture() throws -> AsyncStream<AudioChunk> {
        if meetingIsRecording { throw DictationError.micBusy }
        micHeartbeat.withLock { $0 = .now }
        #if DEBUG
            if testHooks != nil {
                if let error = testHooks?.captureError { throw error }
                let (stream, continuation) = AsyncStream.makeStream(
                    of: AudioChunk.self, bufferingPolicy: .unbounded)
                chunkContinuation = continuation
                captureGeneration = sessionGeneration
                return stream
            }
        #endif
        let (stream, continuation) = AsyncStream.makeStream(
            of: AudioChunk.self,
            bufferingPolicy: .unbounded)
        chunkContinuation = continuation
        do {
            let recorder = MicRecorder()
            let gate = waveformGate
            let heartbeat = micHeartbeat
            try recorder.start(echoCancellation: false) { [weak self] buffer, _ in
                heartbeat.withLock { $0 = .now }
                let level = buffer.rmsLevel
                if gate.shouldPublish(.mic) {
                    Task { @MainActor [weak self] in
                        self?.pushLevel(level)
                    }
                }
                guard let copy = buffer.deepCopy() else { return }
                continuation.yield(AudioChunk(buffer: copy, startSeconds: nil))
            }
            mic = recorder
            captureGeneration = sessionGeneration
            return stream
        } catch {
            continuation.finish()
            if meetingIsRecording { throw DictationError.micBusy }
            throw error
        }
    }

    private var micStallLimit: Duration? {
        #if DEBUG
            if testHooks != nil { return testHooks?.micStallLimit }
        #endif
        return .seconds(3)
    }

    private func watchForMicStall(generation: Int) {
        guard let limit = micStallLimit else { return }
        stallTask?.cancel()
        stallTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: limit / 3)
                guard let self, generation == self.sessionGeneration, self.phase == .listening
                else { return }
                if ContinuousClock.now - self.micHeartbeat.withLock({ $0 }) > limit {
                    let task = self.transcribeTask
                    self.invalidateSession()
                    task?.cancel()
                    self.fail(MicrophoneChanged())
                    return
                }
            }
        }
    }

    private func runEngine(
        chunks: AsyncStream<AudioChunk>, generation: Int
    ) async throws -> String {
        #if DEBUG
            if let transcribe = testHooks?.transcribe {
                return try await transcribe(chunks)
            }
            if testHooks != nil {
                for await _ in chunks {}
                return ""
            }
        #endif
        let locale = Self.preferredLocale()
        switch engineID {
        case .local:
            return try await appleEngine.transcribe(
                locale: locale,
                chunks: chunks,
                onPartial: { [weak self, generation] text in
                    Task { @MainActor [weak self] in
                        self?.publishPreview(text, generation: generation)
                    }
                })
        case .muse:
            guard let apiKey = KeychainStore.get(account: KeychainStore.museAPIKeyAccount) else {
                throw DictationError.museFailed(
                    "Add a Meta API key in Settings → Dictation to use Muse.")
            }
            let biasIDs: [String] = {
                let requested = UserDefaults.standard.string(forKey: "defaultLocale") ?? "auto"
                if requested == "auto" {
                    return LanguageDetection.parseProbeLocales(
                        UserDefaults.standard.string(forKey: "probeLocales"))
                }
                return [requested]
            }()
            let keywords = MuseLanguages.keywords(
                from: UserDefaults.standard.string(forKey: "dictationKeywords") ?? "")
            return try await museEngine.transcribe(
                configuration: .init(
                    apiKey: apiKey,
                    languageBias: MuseLanguages.bias(forLocaleIDs: biasIDs),
                    keywords: keywords),
                chunks: chunks,
                onPartial: { [weak self, generation] text in
                    Task { @MainActor [weak self] in
                        self?.publishPreview(text, generation: generation)
                    }
                })
        }
    }

    private func stop() async {
        guard phase == .listening || phase == .preparing else { return }
        if !hasOpenCapture {
            let task = transcribeTask
            invalidateSession()
            task?.cancel()
            resetToIdle()
            await task?.value
            return
        }
        phase = .processing
        stoppedAt = .now
        pasteTarget = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let generation = sessionGeneration
        if presentsChrome {
            DictationOverlayController.shared.setClickThrough(true)
        }
        chunkContinuation?.finish()
        chunkContinuation = nil
        mic?.stop()
        mic = nil
        await transcribeTask?.value
        if phase == .processing, generation == sessionGeneration {
            resetToIdle()
        }
    }

    private func finish(text: String) async {
        let trimmed = DictationText.resolved(finals: text, partial: preview)
        let generation = sessionGeneration
        finishMic()
        guard !trimmed.isEmpty else {
            if !reachedListening {
                resetToIdle()
                return
            }
            fail(DictationError.empty)
            return
        }
        preview = trimmed
        // Speaking time only: the rewrite's network time is not part of the dictation.
        let duration = (stoppedAt ?? .now).timeIntervalSince(pressStartedAt ?? .now)
        let target =
            stoppedAt == nil
            ? NSWorkspace.shared.frontmostApplication?.processIdentifier : pasteTarget
        let rewritten = await rewriteIfNeeded(trimmed)
        // Esc during the rewrite cancelled the session: nothing to paste.
        guard generation == sessionGeneration else { return }
        unregisterEscape()
        if shouldPaste {
            paste(rewritten, into: target)
        }
        preview = rewritten
        phase = .done
        onCommitted?(rewritten, duration, sourceApp)
        isRewriting = false
        DictationOverlayController.shared.setClickThrough(true)
        scheduleHide()
    }

    private func rewriteIfNeeded(_ text: String) async -> String {
        #if DEBUG
            if testHooks != nil { return text }
        #endif
        let provider = UserDefaults.standard.string(forKey: "dictationRewrite") ?? "off"
        guard provider != "off" else { return text }
        isRewriting = true
        do {
            return try await RewriteClient.rewrite(text)
        } catch {
            if !Task.isCancelled {
                ToastController.shared.show(error.localizedDescription, style: .warning)
            }
            return text
        }
    }

    /// Auto-pastes only into the app that was frontmost when dictation stopped;
    /// the rewrite can take seconds, and the user may have switched apps meanwhile.
    private func paste(_ text: String, into target: pid_t?) {
        let autoPaste = UserDefaults.standard.object(forKey: "dictationAutoPaste") as? Bool ?? true
        let sameApp = NSWorkspace.shared.frontmostApplication?.processIdentifier == target
        if autoPaste, sameApp, PasteService.pastePreservingClipboard(text) {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        if !autoPaste {
            ToastController.shared.show("Copied")
        } else if !sameApp {
            ToastController.shared.show(
                "Copied — app changed, press ⌘V to paste", style: .warning)
        } else {
            ToastController.shared.show(
                "Copied — grant Accessibility to auto-paste", style: .warning)
        }
    }

    private func fail(_ error: Error) {
        finishMic()
        if case .micBusy? = error as? DictationError {
            // The meeting owns the mic until it ends; an overlay offering
            // Retry would only fail the same way.
            resetToIdle()
            if presentsChrome {
                ToastController.shared.show(error.localizedDescription, style: .warning)
            }
            return
        }
        let retryable =
            error is MicrophoneChanged || ((error as? DictationError)?.isRetryable ?? false)
        lastFailureRetryable = retryable
        phase = .failed(error.localizedDescription)
        restoreCaptionsIfRecording()
        // Esc stays registered until the overlay hides, so a failure always has a way out.
        DictationOverlayController.shared.setClickThrough(!retryable)
        scheduleHide()
    }

    private func finishMic() {
        chunkContinuation?.finish()
        chunkContinuation = nil
        mic?.stop()
        mic = nil
    }

    private func invalidateSession() {
        sessionGeneration += 1
        pressEventTimestamp = nil
    }

    private func resetToIdle() {
        finishMic()
        unregisterEscape()
        preview = ""
        waveform = Array(repeating: 0, count: Self.waveformBars)
        phase = .idle
        isToggle = false
        isRewriting = false
        lastFailureRetryable = false
        reachedListening = false
        DictationOverlayController.shared.setVisible(false)
        restoreCaptionsIfRecording()
    }

    private func publishPreview(_ text: String, generation: Int) {
        guard generation == sessionGeneration else { return }
        switch phase {
        case .preparing, .listening, .processing:
            preview = text
        case .idle, .done, .failed:
            return
        }
    }

    private func pushLevel(_ level: Float) {
        guard phase == .listening || phase == .preparing else { return }
        var next = waveform
        if !next.isEmpty { next.removeFirst() }
        next.append(
            WaveformEnvelope.next(
                current: next.last ?? 0,
                target: WaveformGain.display(level)))
        waveform = next
    }

    private func scheduleHide() {
        hideTask?.cancel()
        let delay: Duration =
            switch phase {
            case .done: .milliseconds(720)
            case .failed where lastFailureRetryable: .seconds(5)
            default: .milliseconds(1600)
            }
        hideTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, !phase.isActive else { return }
            resetToIdle()
        }
    }

    private func restoreCaptionsIfRecording() {
        CaptionsOverlayController.shared.setVisible(meetingIsRecording)
    }

    private func registerEscape() {
        HotkeyManager.shared.register(
            id: 4,
            keyCode: UInt32(kVK_Escape),
            modifiers: 0
        ) { [weak self] in
            self?.cancel()
        }
    }

    private func unregisterEscape() {
        HotkeyManager.shared.unregister(id: 4)
    }

    static func preferredLocale() -> Locale {
        let defaults = UserDefaults.standard
        let dictation = defaults.string(forKey: "dictationLocale") ?? "auto"
        if dictation != "auto" { return Locale(identifier: dictation) }
        if let last = defaults.string(forKey: "lastSpeechLocale"), !last.isEmpty, last != "auto" {
            return Locale(identifier: last)
        }
        let meeting = defaults.string(forKey: "defaultLocale") ?? "auto"
        if meeting != "auto" { return Locale(identifier: meeting) }
        let probes = LanguageDetection.parseProbeLocales(defaults.string(forKey: "probeLocales"))
        let current = Locale.current.language.languageCode?.identifier ?? ""
        if let match = probes.first(where: { $0.hasPrefix(current) }) {
            return Locale(identifier: match)
        }
        return Locale(identifier: probes.first ?? "en-US")
    }
}

/// Not a `DictationError` case: meeting code switches over that enum exhaustively.
private struct MicrophoneChanged: LocalizedError {
    var errorDescription: String? { "Microphone changed — try again." }
}

extension DictationError {
    fileprivate var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}

#if DEBUG
    struct DictationTestHooks {
        var beforeCapture: (@MainActor () async -> Void)?
        var captureError: Error?
        var prepareEngine: (@MainActor () async throws -> Void)?
        var transcribe: (@MainActor (AsyncStream<AudioChunk>) async throws -> String)?
        var presentsOverlay = false
        var pastes = false
        var micStallLimit: Duration?
    }
#endif
