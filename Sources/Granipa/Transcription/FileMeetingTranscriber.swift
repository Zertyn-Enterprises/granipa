import AVFoundation
import Foundation
import Speech

/// One SpeechAnalyzer at a time, after Record has stopped. Live analyzers
/// during capture were freezing the UI at ~125% CPU.
enum FileMeetingTranscriber {
    static func transcribe(
        micURL: URL,
        systemURL: URL,
        meetingID: String,
        language: String,
        database: AppDatabase
    ) async {
        let localeID = LanguageDetection.startLocales(
            requested: language,
            last: UserDefaults.standard.string(forKey: "lastSpeechLocale"))[0]
        let locale = Locale(identifier: localeID)
        do {
            try await SpeechModels.ensureInstalled(locale: locale)
        } catch {
            return
        }
        await transcribeFile(
            url: micURL, channel: .mic, locale: locale, meetingID: meetingID,
            database: database)
        await transcribeFile(
            url: systemURL, channel: .system, locale: locale, meetingID: meetingID,
            database: database)
        UserDefaults.standard.set(localeID, forKey: "lastSpeechLocale")
    }

    private static func transcribeFile(
        url: URL,
        channel: AudioChannel,
        locale: Locale,
        meetingID: String,
        database: AppDatabase
    ) async {
        let path = url.path
        guard FileManager.default.isReadableFile(atPath: path) else { return }
        let size =
            (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber)?
            .int64Value ?? 0
        guard size > 2048 else { return }

        do {
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0 else { return }
            let transcriber = SpeechTranscriber(
                locale: locale,
                transcriptionOptions: [],
                reportingOptions: [],
                attributeOptions: [.audioTimeRange, .transcriptionConfidence])
            let analyzer = SpeechAnalyzer(
                modules: [transcriber],
                options: SpeechAnalyzer.Options(
                    priority: .utility,
                    modelRetention: .lingering))
            let resultsTask = Task {
                for try await result in transcriber.results {
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty, result.isFinal else { continue }
                    let start = result.range.start.seconds
                    let end = result.range.end.seconds
                    let segment = TranscriptSegment.new(
                        meetingID: meetingID,
                        channel: channel,
                        speaker: channel == .mic ? "Me" : "Them",
                        text: text,
                        startSeconds: start.isFinite ? start : 0,
                        endSeconds: end.isFinite ? end : (start.isFinite ? start : 0),
                        isFinal: true)
                    try? database.save(segment)
                }
            }
            _ = try await analyzer.analyzeSequence(from: file)
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try? await resultsTask.value
        } catch {
            return
        }
    }
}