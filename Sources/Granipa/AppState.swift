import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    private(set) var database: AppDatabase?
    let recorder = RecordingEngine()
    private(set) var transcription: TranscriptionCoordinator?
    var meetings: [Meeting] = []
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
        } catch {
            loadError = error.localizedDescription
        }
    }

    init(database: AppDatabase) {
        self.database = database
        meetings = (try? database.fetchMeetings()) ?? []
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

        if var finished = meetings.first(where: { $0.id == id }) {
            finished.status = .ready
            update(finished)
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
