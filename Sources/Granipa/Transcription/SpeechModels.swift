import Foundation
import Speech

enum TranscriptionError: LocalizedError {
    case unsupportedLocale(String)
    case noAudioFormat
    case notAvailable

    var errorDescription: String? {
        switch self {
        case .unsupportedLocale(let id):
            return "On-device transcription does not support the language \"\(id)\"."
        case .noAudioFormat:
            return "Could not determine a compatible audio format for transcription."
        case .notAvailable:
            return "On-device transcription is not available on this Mac."
        }
    }
}

enum SpeechModels {
    static func isInstalled(locale: Locale) async -> Bool {
        await SpeechTranscriber.installedLocales
            .contains { $0.identifier(.bcp47) == locale.identifier(.bcp47) }
    }

    static func ensureInstalled(locale: Locale) async throws {
        guard SpeechTranscriber.isAvailable else {
            throw TranscriptionError.notAvailable
        }
        let supported = await SpeechTranscriber.supportedLocales
        guard supported.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) })
        else {
            throw TranscriptionError.unsupportedLocale(locale.identifier)
        }
        if await isInstalled(locale: locale) { return }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [.volatileResults],
            attributeOptions: [.audioTimeRange])
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }
}
