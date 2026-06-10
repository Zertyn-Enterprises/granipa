import Foundation

enum LLMError: LocalizedError {
    case executableNotFound(String)
    case unknownProvider(String)
    case nonZeroExit(Int32, String)
    case terminated
    case emptyOutput

    var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return "Could not find the \"\(name)\" CLI. Is it installed and on your PATH?"
        case .unknownProvider(let id):
            return "Unknown LLM provider \"\(id)\"."
        case .nonZeroExit(let code, let stderr):
            return "LLM CLI exited with code \(code): \(stderr)"
        case .terminated:
            return "LLM CLI timed out and was terminated."
        case .emptyOutput:
            return "LLM CLI returned no output."
        }
    }
}

private final class DataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func set(_ new: Data) {
        lock.lock()
        data = new
        lock.unlock()
    }

    func get() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

enum LLMRunner {
    struct Output: Sendable {
        let stdout: String
        let stderr: String
    }

    static func run(
        executable: URL,
        arguments: [String],
        stdin: String?,
        timeout: TimeInterval
    ) async throws -> Output {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    continuation.resume(
                        returning: try runSync(
                            executable: executable, arguments: arguments,
                            stdin: stdin, timeout: timeout))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func runSync(
        executable: URL,
        arguments: [String],
        stdin: String?,
        timeout: TimeInterval
    ) throws -> Output {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments

        var environment = ProcessInfo.processInfo.environment
        let home = NSHomeDirectory()
        let extraPaths = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        environment["PATH"] = (extraPaths + [environment["PATH"] ?? "/usr/bin:/bin"])
            .joined(separator: ":")
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe = Pipe()
        if stdin != nil {
            process.standardInput = stdinPipe
        } else {
            process.standardInput = FileHandle.nullDevice
        }

        try process.run()

        if let stdin {
            let data = Data(stdin.utf8)
            let writer = stdinPipe.fileHandleForWriting
            DispatchQueue.global(qos: .utility).async {
                try? writer.write(contentsOf: data)
                try? writer.close()
            }
        }

        let watchdog = DispatchWorkItem {
            if process.isRunning {
                process.terminate()
            }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: watchdog)

        // Drain stderr on a second thread so a full pipe can't deadlock the child.
        let stderrBox = DataBox()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            stderrBox.set((try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data())
            group.leave()
        }
        let stdoutData = (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        process.waitUntilExit()
        group.wait()
        watchdog.cancel()

        let stdout = String(decoding: stdoutData, as: UTF8.self)
        let stderr = String(decoding: stderrBox.get(), as: UTF8.self)

        if process.terminationReason == .uncaughtSignal {
            throw LLMError.terminated
        }
        guard process.terminationStatus == 0 else {
            throw LLMError.nonZeroExit(
                process.terminationStatus,
                String(stderr.suffix(500)).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return Output(stdout: stdout, stderr: stderr)
    }
}
