import Foundation
import Observation
import os

/// Post-recording pipeline: transcript (from the recorded files, or the live
/// coordinator draining) → diarize → enhance → ready status and webhooks.
/// Jobs run one at a time in submission order, like the analyzers they drive.
@MainActor
@Observable
final class MeetingProcessor {
    /// What the pipeline needs back from the app: store writes go through
    /// `update` so the in-memory meeting list stays in sync.
    struct Host {
        var update: @MainActor (Meeting) -> Void
        var folder: @MainActor (Meeting) -> Folder?
        var reportError: @MainActor (String) -> Void
    }

    enum Source {
        /// Replaces each channel's transcript with one made from its file,
        /// once that channel's analysis succeeded.
        case files(micURL: URL, systemURL: URL, language: String)
        /// Waits for the live coordinator to finish.
        case live(drain: @MainActor () async -> LiveResult)
    }

    struct LiveResult {
        /// Muse transcribed (and diarized) the system channel.
        var usedMuseForSystem: Bool
        /// Why live transcription failed, if it did (e.g. lines not saved).
        var failure: String?
    }

    enum EnhanceOutcome: Equatable {
        case ran
        case nothingToEnhance
        case alreadyRunning
        case failed(String)
    }

    enum Stage: Equatable, Sendable {
        case transcribingAudio
        case transcribingCall
        case identifyingSpeakers
        case writingNotes

        var title: String {
            switch self {
            case .transcribingAudio: "Transcribing your audio…"
            case .transcribingCall: "Transcribing the call…"
            case .identifyingSpeakers: "Identifying speakers…"
            case .writingNotes: "Writing notes…"
            }
        }
    }

    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "transcription")

    private(set) var processingMeetingID: String?
    private(set) var enhancingMeetingIDs: Set<String> = []
    /// Step of the running job (`processingMeetingID`); nil while a live
    /// coordinator drains.
    private(set) var stage: Stage?
    /// Last enhancement failure per meeting, kept for this session only.
    private(set) var enhanceErrors: [String: String] = [:]

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private let host: Host
    @ObservationIgnored private var jobs: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var tail: Task<Void, Never>?
    @ObservationIgnored private var enhanceTasks: [String: Task<EnhanceOutcome, Never>] = [:]

    init(database: AppDatabase, host: Host) {
        self.database = database
        self.host = host
    }

    func process(meetingID id: String, source: Source) async {
        guard jobs[id] == nil else { return }
        let previous = tail
        let job = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            await run(meetingID: id, source: source)
        }
        jobs[id] = job
        tail = job
        await job.value
        if jobs[id] == job {
            jobs[id] = nil
        }
    }

    /// Drops a job still waiting for its turn. The running job is never
    /// interrupted (analyzers and the LLM CLI do not stop cleanly), so this
    /// returns false for it.
    func cancelQueued(meetingID id: String) -> Bool {
        guard let job = jobs[id] else { return true }
        guard processingMeetingID != id else { return false }
        job.cancel()
        jobs[id] = nil
        return true
    }

    private func run(meetingID id: String, source: Source) async {
        processingMeetingID = id
        defer {
            if processingMeetingID == id {
                processingMeetingID = nil
                stage = nil
            }
        }
        let transcriptionFailed: Bool
        var skipLocalDiarize = false
        switch source {
        case .live(let drain):
            let result = await drain()
            skipLocalDiarize = result.usedMuseForSystem
            transcriptionFailed = result.failure != nil
            if let failure = result.failure {
                Self.log.error(
                    "live transcription failed for \(id, privacy: .public): \(failure, privacy: .public)")
            }
        case .files(let micURL, let systemURL, let language):
            transcriptionFailed = await transcribe(
                meetingID: id, micURL: micURL, systemURL: systemURL, language: language)
        }
        if transcriptionFailed {
            ToastController.shared.show(
                "Transcription failed — your audio was saved", style: .warning)
        }
        stage = .identifyingSpeakers
        await diarize(meetingID: id, skipLocalDiarize: skipLocalDiarize)
        stage = .writingNotes
        // A request that started before this job must not stand in for the
        // pipeline's pass: it read the transcript before diarization.
        if let running = enhanceTasks[id] {
            _ = await running.value
        }
        let enhanced = await runEnhance(meetingID: id)
        finish(meetingID: id)
        if let meeting = try? database.fetchMeeting(id: id) {
            let notice = Self.completionNotice(
                title: meeting.title, transcriptionFailed: transcriptionFailed, enhancement: enhanced)
            NotificationManager.shared.notify(title: notice.title, body: notice.body)
        }
    }

    /// Returns whether transcription failed (a failed channel keeps its old segments).
    private func transcribe(
        meetingID id: String, micURL: URL, systemURL: URL, language: String
    ) async -> Bool {
        stage = .transcribingAudio
        let db = database
        let result = await Task.detached {
            await FileMeetingTranscriber.transcribe(
                micURL: micURL,
                systemURL: systemURL,
                meetingID: id,
                language: language,
                database: db,
                onChannel: { channel in
                    await self.setStage(channel == .mic ? .transcribingAudio : .transcribingCall)
                })
        }.value
        if let detected = result.language {
            saveLanguage(detected, meetingID: id)
        }
        guard case .failed(let failure) = result.outcome else { return false }
        // The underlying error is logged at the catch site in FileMeetingTranscriber.
        Self.log.error(
            "post-meeting transcription failed for \(id, privacy: .public): \(failure.logDescription, privacy: .public)"
        )
        return true
    }

    /// On the main actor, with no suspension between the read and the write,
    /// so no other in-app edit of the meeting can be lost in between.
    private func saveLanguage(_ language: String, meetingID id: String) {
        guard var meeting = try? database.fetchMeeting(id: id), meeting.language != language
        else { return }
        meeting.language = language
        host.update(meeting)
    }

    private func setStage(_ next: Stage) {
        stage = next
    }

    /// What the user is told when a meeting finishes processing.
    static func completionNotice(
        title: String,
        transcriptionFailed: Bool,
        enhancement: EnhanceOutcome
    ) -> (title: String, body: String) {
        if transcriptionFailed {
            return (
                "Transcription failed",
                "\(title): your audio was saved. Open the meeting and choose Transcribe again.")
        }
        switch enhancement {
        case .ran:
            return ("Notes ready", title)
        case .failed(let message):
            return ("Notes not written", "\(title): \(message)")
        case .nothingToEnhance:
            return ("Recording processed", "\(title): no speech or notes to write up.")
        case .alreadyRunning:
            return ("Recording processed", title)
        }
    }

    private func diarize(meetingID: String, skipLocalDiarize: Bool) async {
        let db = database
        let defaults = UserDefaults.standard
        let diarizationEnabled = defaults.object(forKey: "diarizationEnabled") as? Bool ?? true
        let inferNames = defaults.object(forKey: "inferSpeakerNames") as? Bool ?? true
        let providerID = defaults.string(forKey: "llmProvider") ?? "claude"

        if skipLocalDiarize {
            if inferNames {
                try? await DiarizationService.inferNames(
                    meetingID: meetingID, database: db, providerID: providerID)
            }
        } else if diarizationEnabled, let meeting = try? db.fetchMeeting(id: meetingID) {
            // DiarizationService returns before prepareModels when there are
            // no final system segments, so a failed transcription with zero
            // segments is already a cheap no-op here.
            do {
                try await DiarizationService.diarize(
                    meetingID: meetingID,
                    audioSystemPath: meeting.audioSystemPath,
                    database: db,
                    nameInferenceProviderID: inferNames ? providerID : nil)
            } catch {
                // Best-effort: segments keep their "Them" label, but leave evidence.
                Logger(subsystem: "com.zertyn.granipa", category: "diarization")
                    .error("diarization failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Marks the meeting ready and announces it with its final transcript.
    private func finish(meetingID: String) {
        let db = database
        if var finished = try? db.fetchMeeting(id: meetingID) {
            finished.status = .ready
            host.update(finished)
        }

        if let meeting = try? db.fetchMeeting(id: meetingID) {
            let segments = (try? db.fetchSegments(meetingID: meetingID, finalOnly: true)) ?? []
            WebhookService.enqueue(
                event: .meetingCompleted,
                payload: MeetingCompletedPayload(
                    timestamp: .now,
                    meeting: MeetingDetailDTO(meeting, folder: host.folder(meeting)),
                    transcript: segments.map(SegmentDTO.init)),
                database: db)
            Task { await WebhookService.deliverDue(database: db) }
        }
    }

    /// Manual and API requests. While the pipeline owns the meeting they are
    /// refused: its own pass runs once speakers are relabelled.
    @discardableResult
    func enhance(meetingID: String) async -> EnhanceOutcome {
        guard jobs[meetingID] == nil, enhanceTasks[meetingID] == nil else { return .alreadyRunning }
        return await runEnhance(meetingID: meetingID)
    }

    private func runEnhance(meetingID: String) async -> EnhanceOutcome {
        let task = Task { await generateNotes(meetingID: meetingID) }
        enhanceTasks[meetingID] = task
        let outcome = await task.value
        if enhanceTasks[meetingID] == task {
            enhanceTasks[meetingID] = nil
        }
        return outcome
    }

    private func generateNotes(meetingID: String) async -> EnhanceOutcome {
        let db = database
        enhanceErrors[meetingID] = nil
        guard let meeting = try? db.fetchMeeting(id: meetingID) else { return .nothingToEnhance }
        let segments = (try? db.fetchSegments(meetingID: meetingID, finalOnly: true)) ?? []
        let hasNotes = !meeting.notesMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !segments.isEmpty || hasNotes else { return .nothingToEnhance }

        enhancingMeetingIDs.insert(meetingID)
        defer { enhancingMeetingIDs.remove(meetingID) }

        let template =
            meeting.templateID.flatMap { try? db.fetchTemplate(id: $0) }
            ?? MeetingTemplate.builtins.first
        let prompt = EnhancementService.buildPrompt(
            template: template,
            notes: meeting.notesMarkdown,
            transcript: EnhancementService.transcriptText(segments: segments))
        let providerID = UserDefaults.standard.string(forKey: "llmProvider") ?? "claude"

        let raw: String
        do {
            raw = try await LLMService.generate(providerID: providerID, prompt: prompt)
        } catch {
            let message = Self.enhancementFailureMessage(error)
            enhanceErrors[meetingID] = message
            host.reportError(message)
            return .failed(message)
        }
        applyEnhancement(raw: raw, meetingID: meetingID)
        return .ran
    }

    private static func enhancementFailureMessage(_ error: Error) -> String {
        let message = error.localizedDescription
        let lower = message.lowercased()
        let hint =
            lower.contains("login") || lower.contains("auth")
                || lower.contains("credential") || lower.contains("api key")
            ? " The CLI isn't signed in — open Terminal, run it once, and complete the browser login (Settings → AI has a Test button)."
            : ""
        return "Enhancement failed: \(message)\(hint)"
    }

    private func applyEnhancement(raw: String, meetingID: String) {
        let db = database
        guard let result = try? EnhancementService.parse(raw) else {
            // The model replied but we couldn't structure it (e.g. unescaped verbatim
            // quotes or a truncated reply). Keep its work as the report instead of
            // discarding everything, and surface a non-blocking notice.
            guard var updated = try? db.fetchMeeting(id: meetingID) else { return }
            updated.enhancedNotesMarkdown = EnhancementService.salvagedReport(from: raw)
            host.update(updated)
            ToastController.shared.show(
                "Notes saved, but couldn't format fully", style: .warning)
            return
        }

        guard var updated = try? db.fetchMeeting(id: meetingID) else { return }
        updated.summary = result.summary
        updated.enhancedNotesMarkdown = result.enhancedNotes
        updated.actionItemsJSON = ActionItem.encodeList(result.actionItems ?? [])
        updated.emailDraft = result.emailDraft
        if updated.title == "Untitled meeting", let title = result.title, !title.isEmpty {
            updated.title = title
        }
        host.update(updated)
        WebhookService.enqueue(
            event: .notesEnhanced,
            payload: NotesEnhancedPayload(
                timestamp: .now,
                meeting: MeetingDetailDTO(updated, folder: host.folder(updated))),
            database: db)
        Task { await WebhookService.deliverDue(database: db) }
    }
}

