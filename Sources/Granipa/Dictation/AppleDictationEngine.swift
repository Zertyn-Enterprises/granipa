import Foundation

final class AppleDictationEngine: Sendable {
    func transcribe(
        locale: Locale,
        chunks: AsyncStream<AudioChunk>,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        let box = FinalsBox()
        try await transcribeChannel(
            channel: .mic,
            locale: locale,
            chunks: chunks,
            delivery: .realtime
        ) { update in
            let preview = box.consume(update)
            onPartial(preview)
        }
        return box.bestText()
    }
}

/// Accumulates Apple finals on whatever thread SpeechAnalyzer delivers.
enum DictationText {
    static func resolved(finals: String, partial: String) -> String {
        let committed = finals.trimmingCharacters(in: .whitespacesAndNewlines)
        if !committed.isEmpty { return committed }
        return partial.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Accumulates Apple finals on whatever thread SpeechAnalyzer delivers.
/// Volatile (partial) text is kept so a quick release still pastes something.
private final class FinalsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var committed = ""
    private var partial = ""

    func consume(_ update: LiveTranscriptionUpdate) -> String {
        lock.lock()
        defer { lock.unlock() }
        if update.isFinal {
            if committed.isEmpty {
                committed = update.text
            } else {
                committed += " " + update.text
            }
            partial = ""
            return committed
        }
        partial = update.text
        if committed.isEmpty { return partial }
        return committed + " " + partial
    }

    func bestText() -> String {
        lock.lock()
        defer { lock.unlock() }
        return DictationText.resolved(finals: committed, partial: partial)
    }
}
