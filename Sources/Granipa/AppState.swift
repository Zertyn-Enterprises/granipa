import AppKit
import Carbon.HIToolbox
import Foundation
import Observation
import os

@MainActor
@Observable
final class AppState {
    private static let log = Logger(subsystem: "com.zertyn.granipa", category: "transcription")
    private(set) var database: AppDatabase?
    let recorder = RecordingEngine()
    let calendar = CalendarService()
    let detector = MeetingDetector()
    private let apiServer = APIServer()
    private var webhookLoop: Task<Void, Never>?
    private var clipboardMonitor: ClipboardMonitor?
    private var autoStopTask: Task<Void, Never>?
    @ObservationIgnored private var recordingStartTask: Task<Void, Never>?
    private(set) var transcription: TranscriptionCoordinator?
    private(set) var processingMeetingID: String?
    let dictation = DictationController.shared
    private(set) var enhancingMeetingIDs: Set<String> = []
    var meetings: [Meeting] = []
    var templates: [MeetingTemplate] = []
    var webhooks: [Webhook] = []
    var folders: [Folder] = []
    var selectedFolderID: String?
    var searchQuery = ""
    var selectedMeetingID: String?
    var sidebarDestination: SidebarDestination = .home
    var loadError: String?

    var selectedMeeting: Meeting? {
        guard let id = selectedMeetingID else { return nil }
        return meetings.first { $0.id == id }
    }

    func pipelinePhase(for meeting: Meeting) -> MeetingPipelinePhase {
        MeetingPipeline.phase(
            status: meeting.status,
            isRecording: recorder.isRecording && recorder.meetingID == meeting.id,
            transcriptionPhase: recorder.meetingID == meeting.id ? transcription?.phase : nil,
            isEnhancing: enhancingMeetingIDs.contains(meeting.id))
    }

    init() {
        do {
            let db = try AppDatabase.open()
            database = db
            meetings = try db.fetchMeetings()
            // Recover meetings orphaned mid-recording by a quit or crash.
            for index in meetings.indices where meetings[index].status != .ready {
                meetings[index].status = .ready
                try? db.save(meetings[index])
            }
            templates = try db.fetchTemplates()
            webhooks = try db.fetchWebhooks()
            folders = try db.fetchFolders()
            startServices(database: db)
        } catch {
            loadError = error.localizedDescription
        }
        calendar.start()
        setupDetection()
        setupProductivity()
        purgeOldAudio()
        _ = UpdaterManager.shared
    }

    #if DEBUG
    /// `--v2-fixture` launch: the runtime gate has already verified
    /// CFFIXED_USER_HOME points into a throwaway temp home, so AppDatabase and
    /// AppPaths land there naturally. Seeds deterministic rows and starts no
    /// background service, permission probe, or network loop. Does not write
    /// UserDefaults — cfprefsd ignores CFFIXED_USER_HOME.
    init(fixture: V2Fixture) {
        do {
            let db = try AppDatabase.open()
            database = db
            try V2FixtureSeeder.seed(
                fixture, into: db,
                audioDirectory: { try AppPaths.audioDirectory(meetingID: $0) })
            meetings = try db.fetchMeetings()
            templates = try db.fetchTemplates()
            webhooks = try db.fetchWebhooks()
            folders = try db.fetchFolders()
        } catch {
            loadError = error.localizedDescription
        }
    }
    #endif

    private func setupProductivity() {
        if let db = database {
            let monitor = ClipboardMonitor(database: db)
            monitor.start()
            clipboardMonitor = monitor
        }
        ClipboardPanelController.shared.configure(appState: self)
        DictationHistoryPanelController.shared.configure(appState: self)
        CaptionsOverlayController.shared.attach(appState: self)
        DictationOverlayController.shared.attach(dictation)
        dictation.onCommitted = { [weak self] text, duration, appName in
            self?.recordDictation(text: text, duration: duration, sourceApp: appName)
        }
        registerDictationHotkey()
        BatteryService.shared.start()
        ShortcutHub.shared.rebind()
    }

    func setClipboardCaptureEnabled(_ enabled: Bool) {
        if enabled {
            clipboardMonitor?.start()
        } else {
            clipboardMonitor?.stop()
        }
    }

    func registerDictationHotkey() {
        let keyCode = UInt32(
            UserDefaults.standard.object(forKey: "dictationKeyCode") as? Int
                ?? Int(kVK_RightOption))
        let modifiers = UInt32(
            UserDefaults.standard.object(forKey: "dictationModifiers") as? Int ?? 0)
        HotkeyManager.shared.register(
            id: 3,
            keyCode: keyCode,
            modifiers: modifiers,
            onPress: { DictationController.shared.handlePress(at: $0) },
            onRelease: { DictationController.shared.handleRelease(at: $0) }
        )
        if HotkeyBinding.isModifierOnly(keyCode: keyCode, modifiers: modifiers),
            !PasteService.isTrusted
        {
            PasteService.requestTrust()
        }
    }

    func recordDictation(text: String, duration: TimeInterval, sourceApp: String?) {
        guard let db = database, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        let entry = DictationEntry.new(
            text: text, durationSeconds: duration, sourceApp: sourceApp)
        try? db.insertDictationEntry(entry)
        try? db.pruneDictationEntries()
    }

    private func purgeOldAudio() {
        let days = UserDefaults.standard.integer(forKey: "audioRetentionDays")
        guard days > 0, let db = database else { return }
        let cutoff = Date.now.addingTimeInterval(-Double(days) * 86_400)
        for index in meetings.indices {
            var meeting = meetings[index]
            guard meeting.status == .ready,
                (meeting.endedAt ?? meeting.createdAt) < cutoff,
                meeting.audioMicPath != nil || meeting.audioSystemPath != nil,
                recorder.meetingID != meeting.id
            else { continue }
            if let dir = try? AppPaths.audioDirectory(meetingID: meeting.id) {
                try? FileManager.default.removeItem(at: dir)
            }
            meeting.audioMicPath = nil
            meeting.audioSystemPath = nil
            meetings[index] = meeting
            try? db.save(meeting)
        }
    }

    // Watches for the meeting app hanging up while we are still recording.
    private func startMeetingEndWatch() {
        autoStopTask?.cancel()
        autoStopTask = Task { [weak self] in
            var sawMeetingApp = false
            var inactiveSince: Date?
            while !Task.isCancelled {
                guard let self, self.recorder.isRecording else { return }
                if self.detector.meetingAppActive {
                    sawMeetingApp = true
                    inactiveSince = nil
                } else if sawMeetingApp {
                    if let since = inactiveSince {
                        if Date.now.timeIntervalSince(since) > 45 {
                            await self.handleMeetingEnded()
                            return
                        }
                    } else {
                        inactiveSince = .now
                    }
                }
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func handleMeetingEnded() async {
        guard recorder.isRecording else { return }
        switch UserDefaults.standard.string(forKey: "autoStopMode") ?? "ask" {
        case "auto":
            await stopRecording()
            NotificationManager.shared.notify(
                title: "Recording stopped",
                body: "The meeting app hung up, so Grañipa stopped and is processing your notes.")
        case "ask":
            NotificationManager.shared.notifyMeetingEnded()
        default:
            break
        }
    }

    private func setupDetection() {
        NotificationManager.shared.setup()
        NotificationManager.recordHandler = { [weak self] in
            self?.startRecordingFromDetection()
        }
        NotificationManager.stopHandler = { [weak self] in
            Task { await self?.stopRecording() }
        }
        detector.onMeetingDetected = { [weak self] appName in
            guard let self, !self.recorder.isRecording else { return }
            NotificationManager.shared.notifyMeetingDetected(appName: appName)
        }
        let enabled = UserDefaults.standard.object(forKey: "meetingDetectionEnabled") as? Bool ?? true
        if enabled {
            detector.start()
        }
    }

    func startRecordingFromDetection() {
        guard !recorder.isBusy else { return }
        detector.dismiss()
        startRecording()
        NSApp.activate(ignoringOtherApps: true)
    }

    static func apiToken() -> String {
        let defaults = UserDefaults.standard
        if let token = defaults.string(forKey: "apiToken"), !token.isEmpty {
            return token
        }
        let token = (UUID().uuidString + UUID().uuidString)
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
        defaults.set(token, forKey: "apiToken")
        return token
    }

    func startServices(database db: AppDatabase) {
        let defaults = UserDefaults.standard
        let apiEnabled = defaults.object(forKey: "apiEnabled") as? Bool ?? false
        if apiEnabled {
            let port = UInt16(defaults.integer(forKey: "apiPort"))
            let token = Self.apiToken()
            Task {
                try? await apiServer.start(
                    port: port == 0 ? 7799 : port,
                    token: token,
                    database: db,
                    enhanceTrigger: { meetingID in
                        Task { @MainActor [weak self] in
                            await self?.enhance(meetingID: meetingID)
                        }
                    })
            }
        }
        webhookLoop?.cancel()
        webhookLoop = Task { [weak self] in
            while !Task.isCancelled {
                if self?.webhooks.isEmpty == false {
                    await WebhookService.deliverDue(database: db)
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func restartAPIServer() {
        guard let db = database else { return }
        Task {
            await apiServer.stop()
            startServices(database: db)
        }
    }

    init(database: AppDatabase) {
        self.database = database
        meetings = (try? database.fetchMeetings()) ?? []
        templates = (try? database.fetchTemplates()) ?? []
    }

    func refreshMeetings() {
        guard let db = database else { return }
        do {
            meetings = try db.fetchMeetings()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func createMeeting(title: String = "Untitled meeting", calendarEventID: String? = nil) {
        guard let db = database else { return }
        let language = UserDefaults.standard.string(forKey: "defaultLocale") ?? "auto"
        var meeting = Meeting.new(title: title, language: language)
        meeting.calendarEventID = calendarEventID
        meeting.folderID = selectedFolderID
        do {
            try db.save(meeting)
            meetings.insert(meeting, at: 0)
            selectedMeetingID = meeting.id
        } catch {
            loadError = error.localizedDescription
        }
    }

    func startRecording(fromEvent event: CalendarMeeting) {
        createMeeting(title: event.title, calendarEventID: event.id)
        guard let id = selectedMeetingID else { return }
        startRecording(meetingID: id)
    }

    func update(_ meeting: Meeting) {
        guard let db = database else { return }
        do {
            try db.save(meeting)
            if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                meetings[index] = meeting
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    func startRecording(meetingID: String? = nil) {
        #if DEBUG
        if V2FixtureRuntime.isActive { return }
        #endif
        guard database != nil else { return }
        guard recordingStartTask == nil, !recorder.isBusy else { return }
        let targetID: String
        if let meetingID {
            targetID = meetingID
        } else {
            let event = calendar.currentEvent()
            createMeeting(
                title: event?.title ?? "Untitled meeting",
                calendarEventID: event?.id)
            guard let id = selectedMeetingID else { return }
            targetID = id
        }
        recordingStartTask = Task { [weak self] in
            await self?.activateRecording(targetID: targetID)
            self?.recordingStartTask = nil
        }
    }

    private func activateRecording(targetID: String) async {
        guard var meeting = meetings.first(where: { $0.id == targetID }) else { return }
        do {
            let session = try await recorder.start(meetingID: targetID)
            if MeetingASRPolicy.usesLiveASR(), let db = database {
                let coordinator = TranscriptionCoordinator(
                    meetingID: targetID,
                    language: meeting.language,
                    session: session,
                    database: db)
                coordinator.start()
                transcription = coordinator
            }
            meeting.status = .recording
            meeting.startedAt = .now
            update(meeting)
            selectedMeetingID = targetID
            startMeetingEndWatch()
            dictation.meetingIsRecording = true
            CaptionsOverlayController.shared.resetDismissed()
            if MeetingASRPolicy.usesLiveASR(), !dictation.phase.isActive {
                CaptionsOverlayController.shared.setVisible(true)
            }
            if let db = database {
                WebhookService.enqueue(
                    event: .meetingStarted,
                    payload: MeetingStartedPayload(
                        timestamp: .now,
                        meeting: MeetingSummaryDTO(meeting, folder: folder(for: meeting))),
                    database: db)
            }
        } catch is CancellationError {
        } catch {
            loadError = error.localizedDescription
        }
    }

    func stopRecording() async {
        autoStopTask?.cancel()
        autoStopTask = nil
        let wasStarting = recorder.isStarting && !recorder.isRecording
        recordingStartTask?.cancel()
        dictation.meetingIsRecording = false
        CaptionsOverlayController.shared.setVisible(false)
        guard let id = recorder.meetingID, let urls = await recorder.stop() else { return }
        if wasStarting {
            try? FileManager.default.removeItem(at: urls.micURL.deletingLastPathComponent())
            return
        }
        processingMeetingID = id
        defer {
            if processingMeetingID == id {
                processingMeetingID = nil
            }
        }
        // Re-fetch: the transcription coordinator may have written the detected
        // language while the array copy was stale.
        guard let db = database, var meeting = try? db.fetchMeeting(id: id) else {
            if let live = transcription {
                await live.finishAndWait()
            }
            transcription = nil
            return
        }
        meeting.status = .processing
        meeting.endedAt = .now
        meeting.audioMicPath = urls.micURL.path
        meeting.audioSystemPath = urls.systemURL.path
        update(meeting)

        if let live = transcription {
            await live.finishAndWait()
            let usedMuseForSystem = live.systemUsedMuse
            transcription = nil
            await postProcess(meetingID: id, skipLocalDiarize: usedMuseForSystem)
        } else {
            transcription = nil
            let language = meeting.language
            let outcome = await Task.detached {
                await FileMeetingTranscriber.transcribe(
                    micURL: urls.micURL,
                    systemURL: urls.systemURL,
                    meetingID: id,
                    language: language,
                    database: db)
            }.value
            await postProcess(
                meetingID: id,
                skipLocalDiarize: false,
                fileTranscription: outcome)
        }
    }

    func postProcess(
        meetingID: String,
        skipLocalDiarize: Bool = false,
        fileTranscription: FileMeetingTranscriber.Outcome? = nil
    ) async {
        guard let db = database else { return }
        let defaults = UserDefaults.standard
        let diarizationEnabled = defaults.object(forKey: "diarizationEnabled") as? Bool ?? true
        let inferNames = defaults.object(forKey: "inferSpeakerNames") as? Bool ?? true
        let providerID = defaults.string(forKey: "llmProvider") ?? "claude"

        if case .failed(let failure) = fileTranscription {
            // Generic toast for the user; the underlying error is logged at
            // the catch site in FileMeetingTranscriber.
            Self.log.error(
                "post-meeting transcription failed for \(meetingID, privacy: .public): \(failure.logDescription, privacy: .public)"
            )
            ToastController.shared.show(
                "Transcription failed — your audio was saved", style: .warning)
        }

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

        await enhance(meetingID: meetingID)

        if var finished = try? db.fetchMeeting(id: meetingID) {
            finished.status = .ready
            update(finished)
        }

        if let meeting = try? db.fetchMeeting(id: meetingID) {
            let segments = (try? db.fetchSegments(meetingID: meetingID, finalOnly: true)) ?? []
            WebhookService.enqueue(
                event: .meetingCompleted,
                payload: MeetingCompletedPayload(
                    timestamp: .now,
                    meeting: MeetingDetailDTO(meeting, folder: folder(for: meeting)),
                    transcript: segments.map(SegmentDTO.init)),
                database: db)
            Task { await WebhookService.deliverDue(database: db) }
        }
    }

    func enhance(meetingID: String) async {
        guard let db = database, !enhancingMeetingIDs.contains(meetingID) else { return }
        guard let meeting = try? db.fetchMeeting(id: meetingID) else { return }
        let segments = (try? db.fetchSegments(meetingID: meetingID, finalOnly: true)) ?? []
        let hasNotes = !meeting.notesMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard !segments.isEmpty || hasNotes else { return }

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
            let message = error.localizedDescription
            let lower = message.lowercased()
            let hint =
                lower.contains("login") || lower.contains("auth")
                    || lower.contains("credential") || lower.contains("api key")
                ? " The CLI isn't signed in — open Terminal, run it once, and complete the browser login (Settings → AI has a Test button)."
                : ""
            loadError = "Enhancement failed: \(message)\(hint)"
            return
        }

        guard let result = try? EnhancementService.parse(raw) else {
            // The model replied but we couldn't structure it (e.g. unescaped verbatim
            // quotes or a truncated reply). Keep its work as the report instead of
            // discarding everything, and surface a non-blocking notice.
            guard var updated = try? db.fetchMeeting(id: meetingID) else { return }
            updated.enhancedNotesMarkdown = EnhancementService.salvagedReport(from: raw)
            update(updated)
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
        update(updated)
        WebhookService.enqueue(
            event: .notesEnhanced,
            payload: NotesEnhancedPayload(
                timestamp: .now,
                meeting: MeetingDetailDTO(updated, folder: folder(for: updated))),
            database: db)
        Task { await WebhookService.deliverDue(database: db) }
    }

    func folder(for meeting: Meeting) -> Folder? {
        meeting.folderID.flatMap { id in folders.first { $0.id == id } }
    }

    func reveal(_ destination: SidebarDestination) {
        sidebarDestination = destination
        selectedFolderID = nil
        selectedMeetingID = nil
        searchQuery = ""
    }

    func revealFolder(id: String) {
        sidebarDestination = .meetings
        selectedFolderID = id
        selectedMeetingID = nil
        searchQuery = ""
    }

    func createFolder(name: String, team: String?) {
        guard let db = database, !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let folder = Folder.new(name: name, team: team)
            try db.save(folder)
            folders = try db.fetchFolders()
            revealFolder(id: folder.id)
        } catch {
            loadError = error.localizedDescription
        }
    }

    func renameFolder(id: String, name: String) {
        guard let db = database, var folder = folders.first(where: { $0.id == id }) else { return }
        folder.name = name
        do {
            try db.save(folder)
            folders = try db.fetchFolders()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func deleteFolder(id: String) {
        guard let db = database else { return }
        do {
            try db.deleteFolder(id: id)
            folders = try db.fetchFolders()
            if selectedFolderID == id {
                selectedFolderID = nil
            }
            refreshMeetings()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func moveMeeting(meetingID: String, toFolder folderID: String?) {
        guard var meeting = meetings.first(where: { $0.id == meetingID }) else { return }
        meeting.folderID = folderID
        update(meeting)
    }

    func toggleActionItem(meetingID: String, index: Int) {
        guard var meeting = meetings.first(where: { $0.id == meetingID }) else { return }
        var items = ActionItem.decodeList(from: meeting.actionItemsJSON)
        guard items.indices.contains(index) else { return }
        items[index].done = !(items[index].done ?? false)
        meeting.actionItemsJSON = ActionItem.encodeList(items)
        update(meeting)
    }

    func saveWebhook(_ webhook: Webhook) {
        guard let db = database else { return }
        do {
            try db.save(webhook)
            webhooks = try db.fetchWebhooks()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func deleteWebhook(id: String) {
        guard let db = database else { return }
        do {
            try db.deleteWebhook(id: id)
            webhooks = try db.fetchWebhooks()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func saveTemplate(_ template: MeetingTemplate) {
        guard let db = database else { return }
        do {
            try db.save(template)
            templates = try db.fetchTemplates()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func deleteTemplate(id: String) {
        guard let db = database else { return }
        do {
            try db.deleteTemplate(id: id)
            templates = try db.fetchTemplates()
        } catch {
            loadError = error.localizedDescription
        }
    }

    func deleteMeeting(id: String) {
        guard let db = database else { return }
        do {
            try db.deleteMeeting(id: id)
            meetings.removeAll { $0.id == id }
            if selectedMeetingID == id {
                selectedMeetingID = nil
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}
