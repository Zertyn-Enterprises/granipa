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

    let meetingID: String
    private let language: String
    private let database: AppDatabase
    private let micChunks: AsyncStream<AudioChunk>
    private let systemChunks: AsyncStream<AudioChunk>
    private var channelTasks: [Task<Void, Never>] = []

    init(meetingID: String, language: String, session: RecordingSession, database: AppDatabase) {
        self.meetingID = meetingID
        self.language = language
        self.database = database
        self.micChunks = session.micChunks
        self.systemChunks = session.systemChunks
    }

    func start() {
        let locale = Locale(identifier: language)
        let task = Task {
            do {
                try await SpeechModels.ensureInstalled(locale: locale)
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            phase = .live
            launchChannel(.mic, locale: locale, chunks: micChunks)
            launchChannel(.system, locale: locale, chunks: systemChunks)
        }
        channelTasks.append(task)
    }

    func finishAndWait() async {
        if phase == .live || phase == .preparing {
            phase = .finishing
        }
        // Channel tasks can be appended while we await (model install finishing
        // just as the meeting stops), so index instead of iterating a snapshot.
        var index = 0
        while index < channelTasks.count {
            await channelTasks[index].value
            index += 1
        }
        volatileMic = ""
        volatileSystem = ""
        if case .failed = phase {} else {
            phase = .done
        }
    }

    private func launchChannel(_ channel: AudioChannel, locale: Locale, chunks: AsyncStream<AudioChunk>) {
        let task = Task {
            do {
                try await transcribeChannel(channel: channel, locale: locale, chunks: chunks) {
                    update in
                    Task { @MainActor in
                        self.apply(update)
                    }
                }
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
        channelTasks.append(task)
    }

    private func apply(_ update: LiveTranscriptionUpdate) {
        if update.isFinal {
            switch update.channel {
            case .mic: volatileMic = ""
            case .system: volatileSystem = ""
            }
            let segment = TranscriptSegment.new(
                meetingID: meetingID,
                channel: update.channel,
                speaker: update.channel == .mic ? "Me" : "Them",
                text: update.text,
                startSeconds: update.startSeconds ?? 0,
                endSeconds: update.endSeconds ?? update.startSeconds ?? 0,
                isFinal: true)
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
}
