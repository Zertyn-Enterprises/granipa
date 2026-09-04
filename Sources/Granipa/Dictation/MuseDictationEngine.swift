import AVFoundation
import Foundation

final class MuseDictationEngine: Sendable {
    static let modelID = "muse-voice-transcribe-1.0"

    struct Configuration: Sendable {
        var apiKey: String
        var languageBias: [String]
        var keywords: [String]
    }

    func transcribe(
        configuration: Configuration,
        chunks: AsyncStream<AudioChunk>,
        onPartial: @escaping @Sendable (String) -> Void
    ) async throws -> String {
        guard let targetFormat = PCM16Encoder.format24kMono() else {
            throw DictationError.audioFormat
        }
        let sessionID = UUID().uuidString
        guard let url = URL(string: "wss://api.meta.ai/v1/asr/realtime?sessionId=\(sessionID)")
        else {
            throw DictationError.museConnect
        }

        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()

        var handshake: [String: Any] = [
            "authorization": ["accessToken": "Bearer \(configuration.apiKey)"],
            "audioEncoding": "PCM_24KHZ",
            "model": Self.modelID,
            "mode": "PUSH_TO_TALK",
            "partialMode": "CUMULATIVE",
            "emitAudioProgress": false,
            "zdrOverride": true,
        ]
        if !configuration.languageBias.isEmpty {
            handshake["languageBias"] = configuration.languageBias
        }
        if !configuration.keywords.isEmpty {
            handshake["keywords"] = configuration.keywords
        }
        let handshakeData = try JSONSerialization.data(withJSONObject: handshake)
        guard let handshakeJSON = String(data: handshakeData, encoding: .utf8) else {
            socket.cancel(with: .goingAway, reason: nil)
            throw DictationError.museConnect
        }
        try await socket.send(.string(handshakeJSON))

        let ack = try await receiveJSON(from: socket)
        if case .error(let message) = MuseEventParser.parse(ack) {
            socket.cancel(with: .goingAway, reason: nil)
            throw DictationError.museFailed(message)
        }
        guard case .handshake = MuseEventParser.parse(ack) else {
            socket.cancel(with: .goingAway, reason: nil)
            throw DictationError.museConnect
        }

        let finals = FinalTextBox()
        let receiver = Task {
            do {
                while !Task.isCancelled {
                    let json = try await receiveJSON(from: socket)
                    switch MuseEventParser.parse(json) {
                    case .transcript(let text, _):
                        finals.replace(text)
                        onPartial(text)
                    case .speechComplete(let text):
                        finals.replace(text)
                        onPartial(text)
                    case .error(let message):
                        throw DictationError.museFailed(message)
                    default:
                        break
                    }
                }
            } catch is CancellationError {
                return
            } catch let error as DictationError {
                throw error
            } catch {
                // Socket close after a successful endStream is the happy path.
                return
            }
        }

        let converter = BufferConverter()
        do {
            for await chunk in chunks {
                guard let converted = try? converter.convert(chunk.buffer, to: targetFormat),
                    let pcm = PCM16Encoder.data(from: converted), !pcm.isEmpty
                else { continue }
                try await socket.send(.data(pcm))
            }
            try await socket.send(.string(#"{"type":"endStream"}"#))
            try await withTimeout(seconds: 8) {
                try await receiver.value
            }
        } catch is CancellationError {
            receiver.cancel()
            socket.cancel(with: .goingAway, reason: nil)
            throw DictationError.cancelled
        } catch {
            receiver.cancel()
            socket.cancel(with: .goingAway, reason: nil)
            if !finals.current().isEmpty { return finals.current() }
            throw error
        }

        socket.cancel(with: .normalClosure, reason: nil)
        let text = finals.current()
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw DictationError.empty
        }
        return text
    }

    private func receiveJSON(from socket: URLSessionWebSocketTask) async throws -> String {
        let message = try await socket.receive()
        switch message {
        case .string(let text):
            return text
        case .data(let data):
            return String(data: data, encoding: .utf8) ?? ""
        @unknown default:
            return ""
        }
    }

    private func withTimeout(seconds: Double, operation: @escaping @Sendable () async throws -> Void)
        async throws
    {
        try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await operation()
                return true
            }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                return false
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }
}

private final class FinalTextBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func replace(_ value: String) {
        lock.lock()
        text = value
        lock.unlock()
    }

    func current() -> String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}

enum DictationError: LocalizedError {
    case micBusy
    case audioFormat
    case museConnect
    case museFailed(String)
    case empty
    case cancelled

    /// One retry is worth it when the cause may have cleared on its own
    /// (silence, a busy mic, a transient connection). A rejected server
    /// response or a cancellation will fail identically again.
    var isRetryable: Bool {
        switch self {
        case .empty, .micBusy, .audioFormat, .museConnect: true
        case .museFailed, .cancelled: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .micBusy:
            return "Can't use the microphone while a meeting is recording."
        case .audioFormat:
            return "Could not encode microphone audio."
        case .museConnect:
            return "Could not reach Muse Voice Transcribe."
        case .museFailed(let message):
            return message
        case .empty:
            return "Didn't catch that — try again."
        case .cancelled:
            return nil
        }
    }
}
