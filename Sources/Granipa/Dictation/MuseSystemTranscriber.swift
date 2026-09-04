import AVFoundation
import Foundation

/// Streams the meeting *system* channel to Muse. The mic never goes here.
///
/// The chunks stream is single-consumer: once this function starts iterating
/// it, no fallback can replay it. Transport failures after the first chunk
/// therefore never throw — the session reconnects internally (bounded) and
/// reports degradation through `onStatus` (nil = a warned connection
/// recovered). Only failures before the first chunk propagate, so the
/// coordinator's Apple fallback always receives an unconsumed stream.
enum MuseSystemTranscriber {
    /// Muse closes sessions at 60 minutes; rotate while we still control it.
    static let sessionRotateInterval: TimeInterval = 55 * 60
    static let maxErrorReconnects = 5
    /// Muse caps send-ahead at ~5s; after a reconnect pause the backlog older
    /// than this is dropped instead of burst-sent.
    static let staleChunkThreshold: TimeInterval = 4

    static func transcribe(
        chunks: AsyncStream<AudioChunk>,
        configuration: MuseDictationEngine.Configuration,
        onUpdate: @escaping @Sendable (LiveTranscriptionUpdate) -> Void,
        onStatus: @escaping @Sendable (String?) -> Void
    ) async throws {
        guard let targetFormat = PCM16Encoder.format24kMono() else {
            throw DictationError.audioFormat
        }
        let clock = MeetingClock()
        let session = Session(configuration: configuration, clock: clock, onUpdate: onUpdate)
        // Pre-consume: a failure here leaves `chunks` untouched for the fallback.
        try await session.connect()

        let converter = BufferConverter()
        var newestStart: Double = 0
        var degradedReported = false
        for await chunk in chunks {
            if let start = chunk.startSeconds {
                if start > newestStart { newestStart = start }
                // Backlog accumulated during a reconnect: too old for Muse's
                // send-ahead budget, and the gap is silence-padded in the m4a.
                if newestStart - start > staleChunkThreshold { continue }
                clock.advance(to: start)
            }
            guard
                let converted = try? converter.convert(chunk.buffer, to: targetFormat),
                let pcm = PCM16Encoder.data(from: converted), !pcm.isEmpty
            else { continue }

            if await session.isExpired() {
                await session.rotate()
            }
            if await session.isDead {
                let revived = await session.revive()
                if !revived, !degradedReported {
                    degradedReported = true
                    onStatus("Them transcription stopped — Muse connection lost.")
                } else if revived, degradedReported {
                    // A reconnect succeeded after the user was warned.
                    onStatus(nil)
                }
            }
            let sessionDead = await session.isDead
            if !sessionDead {
                await session.send(pcm)
            }
        }

        if await session.isDead {
            if !degradedReported {
                onStatus("Them transcription stopped — Muse connection lost.")
            }
        } else {
            await session.finishAndDrain()
        }
    }

    fileprivate static func receiveJSON(from socket: URLSessionWebSocketTask) async throws -> String {
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
}

/// One Muse WebSocket session. Actor confinement keeps socket + receiver
/// consistent across the consuming loop, reconnects, and session rotation.
private actor Session {
    private let configuration: MuseDictationEngine.Configuration
    private let clock: MeetingClock
    private let onUpdate: @Sendable (LiveTranscriptionUpdate) -> Void

    private var socket: URLSessionWebSocketTask?
    private var drainTask: Task<Void, Never>?
    private var startedAt = Date.now
    private var dead = true
    private var reconnectsUsed = 0

    init(
        configuration: MuseDictationEngine.Configuration,
        clock: MeetingClock,
        onUpdate: @escaping @Sendable (LiveTranscriptionUpdate) -> Void
    ) {
        self.configuration = configuration
        self.clock = clock
        self.onUpdate = onUpdate
    }

    var isDead: Bool { dead }

    func isExpired(now: Date = .now) -> Bool {
        !dead && now.timeIntervalSince(startedAt) >= MuseSystemTranscriber.sessionRotateInterval
    }

    func connect() async throws {
        do {
            try await connectFresh()
        } catch {
            await markDead()
            throw error
        }
    }

    /// Bring a dead session back, consuming from a bounded budget so a
    /// persistently failing network degrades to dropped audio instead of a
    /// reconnect loop. Rotation does not consume this budget.
    func revive() async -> Bool {
        guard dead else { return true }
        guard reconnectsUsed < MuseSystemTranscriber.maxErrorReconnects else { return false }
        reconnectsUsed += 1
        do {
            try await connectFresh()
            return true
        } catch {
            return false
        }
    }

    /// Planned end-of-life swap: drain pending results, open a fresh session.
    /// A failed swap must land in `dead` so the budgeted revive path (and its
    /// warning) takes over — otherwise an expired session retries a fresh
    /// handshake on every chunk with no bound.
    func rotate() async {
        guard !dead else { return }
        await finishAndDrain()
        reconnectsUsed = 0
        do {
            try await connectFresh()
        } catch {
            await markDead()
        }
    }

    func send(_ data: Data) async {
        guard let socket, !dead else { return }
        do {
            try await socket.send(.data(data))
        } catch {
            await markDead()
        }
    }

    func finishAndDrain() async {
        guard let socket, !dead else { return }
        try? await socket.send(.string(#"{"type":"endStream"}"#))
        if let drain = drainTask {
            _ = try? await Self.withTimeout(seconds: 12) {
                _ = await drain.value
            }
        }
        socket.cancel(with: .normalClosure, reason: nil)
        self.socket = nil
        drainTask = nil
    }

    private func connectFresh() async throws {
        if let socket {
            socket.cancel(with: .goingAway, reason: nil)
            self.socket = nil
        }
        drainTask?.cancel()
        drainTask = nil

        let sessionID = UUID().uuidString
        guard let url = URL(string: "wss://api.meta.ai/v1/asr/realtime?sessionId=\(sessionID)")
        else {
            throw DictationError.museConnect
        }
        let socket = URLSession.shared.webSocketTask(with: url)
        socket.resume()
        self.socket = socket

        var handshake: [String: Any] = [
            "authorization": ["accessToken": "Bearer \(configuration.apiKey)"],
            "audioEncoding": "PCM_24KHZ",
            "model": MuseDictationEngine.modelID,
            "mode": "DIARIZATION",
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
            throw DictationError.museConnect
        }
        try await socket.send(.string(handshakeJSON))

        let ack = try await MuseSystemTranscriber.receiveJSON(from: socket)
        switch MuseEventParser.parse(ack) {
        case .handshake:
            break
        case .error(let message):
            throw DictationError.museFailed(message)
        default:
            throw DictationError.museConnect
        }

        dead = false
        startedAt = .now
        // Speaker labels are per-session; the previous session's last label
        // may not exist in the new one, but timestamps continue from the clock.
        drainTask = Task {
            await runReceiver(on: socket)
        }
    }

    private func runReceiver(on socket: URLSessionWebSocketTask) async {
        do {
            while !Task.isCancelled {
                let json = try await MuseSystemTranscriber.receiveJSON(from: socket)
                let now = clock.seconds()
                switch MuseEventParser.parse(json) {
                case .speechStart:
                    clock.markTurn(at: now)
                case .speaker(let label):
                    clock.setSpeaker(label)
                case .transcript(let text, let isFinal):
                    emit(text: text, isFinal: isFinal, at: now)
                case .speechComplete(let text):
                    emit(text: text, isFinal: true, at: now)
                case .error:
                    await markDead()
                    return
                case .handshake, .ignored:
                    break
                }
            }
        } catch {
            // A close after a successful endStream is the happy path; anything
            // else leaves `dead` as the send path set it.
        }
    }

    private func emit(text: String, isFinal: Bool, at now: Double) {
        onUpdate(
            LiveTranscriptionUpdate(
                channel: .system,
                localeID: "muse",
                text: text,
                startSeconds: clock.turnStart(),
                endSeconds: now,
                isFinal: isFinal,
                confidence: nil,
                speaker: clock.speakerName()))
    }

    private func markDead() {
        guard !dead else { return }
        dead = true
        drainTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
    }

    private static func withTimeout(
        seconds: Double, operation: @escaping @Sendable () async throws -> Void
    ) async throws {
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

final class MeetingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var secondsValue: Double = 0
    private var turnStartValue: Double = 0
    private var speaker: String = "Them"

    func advance(to seconds: Double) {
        lock.lock()
        secondsValue = seconds
        lock.unlock()
    }

    func seconds() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return secondsValue
    }

    func markTurn(at seconds: Double) {
        lock.lock()
        turnStartValue = seconds
        lock.unlock()
    }

    func turnStart() -> Double {
        lock.lock()
        defer { lock.unlock() }
        return turnStartValue
    }

    func setSpeaker(_ label: String) {
        lock.lock()
        speaker = label.isEmpty ? "Them" : "Speaker \(label)"
        lock.unlock()
    }

    func speakerName() -> String {
        lock.lock()
        defer { lock.unlock() }
        return speaker
    }
}
