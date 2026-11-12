import Foundation

/// Waits for `operation` at most `seconds`. A task group cannot do this: it
/// waits for every child, and `Task.value` or a pending socket receive ignores
/// cancellation. Here the first finisher resumes the caller; on timeout
/// `onTimeout` must tear down whatever the operation is blocked on.
/// Returns false when the deadline won.
enum AsyncDeadline {
    @discardableResult
    static func wait(
        seconds: Double,
        onTimeout: @escaping @Sendable () -> Void,
        operation: @escaping @Sendable () async throws -> Void
    ) async throws -> Bool {
        let race = Race()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                race.arm(continuation)
                race.attach([
                    Task {
                        do {
                            try await operation()
                            race.finish(.success(true))
                        } catch {
                            race.finish(.failure(error))
                        }
                    },
                    Task {
                        try? await Task.sleep(for: .seconds(seconds))
                        if race.finish(.success(false)) { onTimeout() }
                    },
                ])
            }
        } onCancel: {
            race.finish(.failure(CancellationError()))
        }
    }
}

private final class Race: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Error>?
    private var result: Result<Bool, Error>?
    private var tasks: [Task<Void, Never>] = []

    func arm(_ continuation: CheckedContinuation<Bool, Error>) {
        lock.lock()
        if let result {
            lock.unlock()
            continuation.resume(with: result)
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func attach(_ newTasks: [Task<Void, Never>]) {
        lock.lock()
        let done = result != nil
        if !done { tasks = newTasks }
        lock.unlock()
        if done { newTasks.forEach { $0.cancel() } }
    }

    /// First caller wins; later results are dropped.
    @discardableResult
    func finish(_ value: Result<Bool, Error>) -> Bool {
        lock.lock()
        guard result == nil else {
            lock.unlock()
            return false
        }
        result = value
        let continuation = self.continuation
        self.continuation = nil
        let tasks = self.tasks
        self.tasks = []
        lock.unlock()
        continuation?.resume(with: value)
        tasks.forEach { $0.cancel() }
        return true
    }
}
