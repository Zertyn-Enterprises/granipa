import Foundation

/// Drops audio-level updates that would only spam the main actor.
final class LevelGate: @unchecked Sendable {
    private let lock = NSLock()
    private var lastAt: [AudioChannel: Date] = [:]
    private let minInterval: TimeInterval

    init(minInterval: TimeInterval = 0.25) {
        self.minInterval = minInterval
    }

    func shouldPublish(_ channel: AudioChannel, _ level: Float) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let now = Date()
        if let previous = lastAt[channel], now.timeIntervalSince(previous) < minInterval {
            return false
        }
        lastAt[channel] = now
        return true
    }
}
