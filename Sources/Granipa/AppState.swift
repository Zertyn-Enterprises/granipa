import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private(set) var database: AppDatabase?
    let recorder = RecordingEngine()
    private(set) var transcription: TranscriptionCoordinator?
    private(set) var enhancingMeetingIDs: Set<String> = []
    var meetings: [Meeting] = []
    var templates: [MeetingTemplate] = []
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
            templates = try db.fetchTemplates()
        } catch {
            loadError = error.localizedDescription
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

    func createMeeting() {
        guard let db = database else { return }
        let language = UserDefaults.standard.string(forKey: "defaultLocale") ?? "en-US"
        let meeting = Meeting.new(title: "Untitled meeting", language: language)
        do {
            try db.save(meeting)
            meetings.insert(meeting, at: 0)
            selectedMeetingID = meeting.id
        } catch {
            loadError = error.localizedDescription
        }
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
            createMeeting()
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
        } catch {
            loadError = "Enhancement failed: \(error.localizedDescription)"
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
