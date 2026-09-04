import AppKit
import AVFoundation
import Carbon.HIToolbox
import Foundation
import Observation

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
    private var sourceApp: String?
    private var sessionGeneration = 0
    private var chunkContinuation: AsyncStream<AudioChunk>.Continuation?
    private var transcribeTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?
    private var mic: MicRecorder?
    private let appleEngine = AppleDictationEngine()
    private let museEngine = MuseDictationEngine()
    @ObservationIgnored private let waveformGate = LevelGate(minInterval: 0.08)

    private init() {}

    static var shortcutLabel: String {
        let keyCode = UserDefaults.standard.object(forKey: "dictationKeyCode") as? Int
            ?? Int(kVK_RightOption)
        let modifiers = UserDefaults.standard.object(forKey: "dictationModifiers") as? Int ?? 0
        if keyCode == Int(kVK_RightCommand) { return "Right ⌘" }
        if keyCode == Int(kVK_Space), modifiers == Int(optionKey) { return "⌥ Space" }
        return "Right ⌥"
    }

    func handlePress() {
        switch phase {
        case .preparing:
            cancel()
        case .listening where isToggle:
            Task { await stop() }
        case .idle, .done, .failed:
            start()
        default:
            break
        }
    }

    func handleRelease() {
        guard phase == .listening || phase == .preparing, !isToggle else { return }
        let held = Date.now.timeIntervalSince(pressStartedAt ?? .now)
        switch DictationTrigger.actionOnRelease(held: held) {
        case .keepAsToggle:
            isToggle = true
            unregisterEscape()
        case .stop:
            Task { await stop() }
        }
    }

    func toggleFromMenu() {
        if phase.isActive {
            Task { await stop() }
        } else {
            isToggle = true
            start()
        }
    }

    func retry() {
        guard case .failed = phase, lastFailureRetryable else { return }
        start()
    }

    func cancel() {
        sessionGeneration += 1
        transcribeTask?.cancel()
        finishMic()
        unregisterEscape()
        preview = ""
        waveform = Array(repeating: 0, count: Self.waveformBars)
        phase = .idle
        isToggle = false
        isRewriting = false
        lastFailureRetryable = false
        DictationOverlayController.shared.setVisible(false)
        restoreCaptionsIfRecording()
    }

    private func start() {
        hideTask?.cancel()
        pressStartedAt = .now
        isToggle = false
        isRewriting = false
        lastFailureRetryable = false
        preview = ""
        waveform = Array(repeating: 0, count: Self.waveformBars)
        engineID = DictationEngineID(
            rawValue: UserDefaults.standard.string(forKey: "dictationEngine") ?? "local")
            ?? .local
        sessionGeneration += 1
        let generation = sessionGeneration
        let front = NSWorkspace.shared.frontmostApplication
        sourceApp =
            front?.bundleIdentifier == Bundle.main.bundleIdentifier
            ? nil : front?.localizedName
        phase = .preparing
        DictationOverlayController.shared.attach(self)
        DictationOverlayController.shared.setClickThrough(false)
        DictationOverlayController.shared.setVisible(true)
        CaptionsOverlayController.shared.setVisible(false)
        registerEscape()

        transcribeTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try self.beginCapture()
                guard !Task.isCancelled, generation == self.sessionGeneration else { return }
                self.phase = .listening
                DictationOverlayController.shared.setClickThrough(false)
                try await self.prepareEngine()
                guard !Task.isCancelled, generation == self.sessionGeneration else { return }
                let text = try await self.runEngine(chunks: stream)
                guard !Task.isCancelled, generation == self.sessionGeneration else { return }
                await self.finish(text: text)
            } catch is CancellationError {
                return
            } catch let error as DictationError where error.isCancelled {
                return
            } catch {
                guard generation == self.sessionGeneration else { return }
                self.fail(error)
            }
        }
    }

    private func prepareEngine() async throws {
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

    func beginCapture() throws -> AsyncStream<AudioChunk> {
        if meetingIsRecording { throw DictationError.micBusy }
        let (stream, continuation) = AsyncStream.makeStream(
            of: AudioChunk.self,
            bufferingPolicy: .unbounded)
        chunkContinuation = continuation
        do {
            let recorder = MicRecorder()
            let echo = meetingIsRecording
                ? (UserDefaults.standard.object(forKey: "echoCancellation") as? Bool ?? true)
                : false
            let gate = waveformGate
            try recorder.start(echoCancellation: echo) { [weak self] buffer, _ in
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
            return stream
        } catch {
            continuation.finish()
            if meetingIsRecording { throw DictationError.micBusy }
            throw error
        }
    }

    private func runEngine(chunks: AsyncStream<AudioChunk>) async throws -> String {
        let locale = Self.preferredLocale()
        switch engineID {
        case .local:
            return try await appleEngine.transcribe(
                locale: locale,
                chunks: chunks,
                onPartial: { [weak self] text in
                    Task { @MainActor [weak self] in
                        self?.preview = text
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
                onPartial: { [weak self] text in
                    Task { @MainActor [weak self] in
                        self?.preview = text
                    }
                })
        }
    }

    private func stop() async {
        guard phase == .listening || phase == .preparing else { return }
        phase = .processing
        DictationOverlayController.shared.setClickThrough(true)
        unregisterEscape()
        chunkContinuation?.finish()
        chunkContinuation = nil
        mic?.stop()
        mic = nil
        await transcribeTask?.value
    }

    private func finish(text: String) async {
        let trimmed = DictationText.resolved(finals: text, partial: preview)
        finishMic()
        unregisterEscape()
        guard !trimmed.isEmpty else {
            fail(DictationError.empty)
            return
        }
        preview = trimmed
        let rewritten = await rewriteIfNeeded(trimmed)
        paste(rewritten)
        preview = rewritten
        phase = .done
        let duration = Date.now.timeIntervalSince(pressStartedAt ?? .now)
        onCommitted?(rewritten, duration, sourceApp)
        isRewriting = false
        DictationOverlayController.shared.setClickThrough(true)
        scheduleHide()
    }

    private func rewriteIfNeeded(_ text: String) async -> String {
        let provider = UserDefaults.standard.string(forKey: "dictationRewrite") ?? "off"
        guard provider != "off" else { return text }
        isRewriting = true
        do {
            return try await RewriteClient.rewrite(text)
        } catch {
            ToastController.shared.show(error.localizedDescription, style: .warning)
            return text
        }
    }

    private func paste(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let autoPaste = UserDefaults.standard.object(forKey: "dictationAutoPaste") as? Bool ?? true
        if autoPaste {
            if PasteService.pasteToFrontmostApp() {
                return
            }
            ToastController.shared.show(
                "Copied — grant Accessibility to auto-paste", style: .warning)
        } else {
            ToastController.shared.show("Copied")
        }
    }

    private func fail(_ error: Error) {
        finishMic()
        unregisterEscape()
        let retryable = (error as? DictationError)?.isRetryable ?? false
        lastFailureRetryable = retryable
        phase = .failed(error.localizedDescription)
        if retryable {
            DictationOverlayController.shared.setClickThrough(false)
        } else {
            DictationOverlayController.shared.setClickThrough(true)
            scheduleHide()
        }
    }

    private func finishMic() {
        chunkContinuation?.finish()
        chunkContinuation = nil
        mic?.stop()
        mic = nil
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
        hideTask = Task {
            try? await Task.sleep(for: .milliseconds(phase == .done ? 720 : 1600))
            guard !Task.isCancelled else { return }
            if !phase.isActive {
                phase = .idle
                preview = ""
                isToggle = false
                DictationOverlayController.shared.setVisible(false)
                restoreCaptionsIfRecording()
            }
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

extension DictationError {
    fileprivate var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}
