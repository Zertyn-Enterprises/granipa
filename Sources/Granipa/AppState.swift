import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private(set) var database: AppDatabase?
    let recorder = RecordingEngine()
    let calendar = CalendarService()
    let detector = MeetingDetector()
    private let apiServer = APIServer()
    private var webhookLoop: Task<Void, Never>?
    private(set) var transcription: TranscriptionCoordinator?
    private(set) var enhancingMeetingIDs: Set<String> = []
    var meetings: [Meeting] = []
    var templates: [MeetingTemplate] = []
    var webhooks: [Webhook] = []
    var selectedMeetingID: String?
    var loadError: String?

    var selectedMeeting: Meeting? {
        guard let id = selectedMeetingID else { return nil }
        return meetings.first { $0.id == id }
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
            startServices(database: db)
        } catch {
            loadError = error.localizedDescription
        }
        calendar.start()
        setupDetection()
    }

    private func setupDetection() {
        NotificationManager.shared.setup()
        NotificationManager.recordHandler = { [weak self] in
            self?.startRecordingFromDetection()
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
        guard !recorder.isRecording else { return }
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
        let apiEnabled = defaults.object(forKey: "apiEnabled") as? Bool ?? true
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
        webhookLoop = Task {
            while !Task.isCancelled {
                await WebhookService.deliverDue(database: db)
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
        let language = UserDefaults.standard.string(forKey: "defaultLocale") ?? "en-US"
        var meeting = Meeting.new(title: title, language: language)
        meeting.calendarEventID = calendarEventID
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
        guard database != nil else { return }
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
        guard var meeting = meetings.first(where: { $0.id == targetID }) else { return }
        do {
            let session = try recorder.start(meetingID: targetID)
            if let db = database {
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
            if let db = database {
                WebhookService.enqueue(
                    event: .meetingStarted,
                    payload: MeetingStartedPayload(timestamp: .now, meeting: MeetingSummaryDTO(meeting)),
                    database: db)
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard let id = recorder.meetingID, let urls = recorder.stop() else { return }
        guard var meeting = meetings.first(where: { $0.id == id }) else { return }
        meeting.status = .processing
        meeting.endedAt = .now
        meeting.audioMicPath = urls.micURL.path
        meeting.audioSystemPath = urls.systemURL.path
        update(meeting)

        await transcription?.finishAndWait()
        transcription = nil

        await postProcess(meetingID: id)
    }

    func postProcess(meetingID: String) async {
        guard let db = database else { return }
        let defaults = UserDefaults.standard
        let diarizationEnabled = defaults.object(forKey: "diarizationEnabled") as? Bool ?? true
        let inferNames = defaults.object(forKey: "inferSpeakerNames") as? Bool ?? true
        let providerID = defaults.string(forKey: "llmProvider") ?? "claude"

        if diarizationEnabled, let meeting = try? db.fetchMeeting(id: meetingID) {
            do {
                try await DiarizationService.diarize(
                    meetingID: meetingID,
                    audioSystemPath: meeting.audioSystemPath,
                    database: db,
                    nameInferenceProviderID: inferNames ? providerID : nil)
            } catch {
                // Diarization is best-effort; segments keep their "Them" label.
            }
        }

        await enhance(meetingID: meetingID)

        if var finished = meetings.first(where: { $0.id == meetingID }) {
            finished.status = .ready
            update(finished)
        }

        if let meeting = try? db.fetchMeeting(id: meetingID) {
            let segments = (try? db.fetchSegments(meetingID: meetingID, finalOnly: true)) ?? []
            WebhookService.enqueue(
                event: .meetingCompleted,
                payload: MeetingCompletedPayload(
                    timestamp: .now,
                    meeting: MeetingDetailDTO(meeting),
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

        do {
            let raw = try await LLMService.generate(providerID: providerID, prompt: prompt)
            let result = try EnhancementService.parse(raw)
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
                payload: NotesEnhancedPayload(timestamp: .now, meeting: MeetingDetailDTO(updated)),
                database: db)
            Task { await WebhookService.deliverDue(database: db) }
        } catch {
            loadError = "Enhancement failed: \(error.localizedDescription)"
        }
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
