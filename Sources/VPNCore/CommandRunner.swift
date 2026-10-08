import Foundation
import Darwin

public struct CommandResult {
    public let output: String
    public let exitCode: Int32

    public init(output: String, exitCode: Int32 = 0) {
        self.output = output
        self.exitCode = exitCode
    }
}

public enum CommandError: Error, LocalizedError, Equatable {
    case timedOut, failed, outputTooLarge

    public var errorDescription: String? {
        switch self {
        case .timedOut: return "The client did not respond in time."
        case .failed: return "The client could not complete the request."
        case .outputTooLarge: return "The client returned an unexpectedly large response."
        }
    }
}

public protocol CommandExecuting {
    func run(_ executable: URL, arguments: [String], environment: [String: String],
             timeout: TimeInterval) async throws -> CommandResult
}

private final class OutputBuffer {
    private let lock = NSLock()
    private var data = Data()
    private var overflow = false
    private let limit = 262_144

    func append(_ chunk: Data) {
        lock.lock()
        defer { lock.unlock() }
        let remaining = max(0, limit - data.count)
        data.append(chunk.prefix(remaining))
        if chunk.count > remaining { overflow = true }
    }

    func result() -> (String, Bool) {
        lock.lock()
        defer { lock.unlock() }
        return (String(decoding: data, as: UTF8.self), overflow)
    }
}

public final class CommandRunner: CommandExecuting {
    public init() {}

    public func run(_ executable: URL, arguments: [String], environment: [String: String] = [:],
                    timeout: TimeInterval = 5) async throws -> CommandResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = arguments
                process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
                process.standardInput = FileHandle.nullDevice
                let stdout = Pipe()
                let stderr = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                let completed = DispatchSemaphore(value: 0)
                process.terminationHandler = { _ in completed.signal() }
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: CommandError.failed)
                    return
                }

                let output = OutputBuffer()
                let errors = OutputBuffer()
                let readers = DispatchGroup()
                for (pipe, buffer) in [(stdout, output), (stderr, errors)] {
                    readers.enter()
                    DispatchQueue.global(qos: .utility).async {
                        defer { readers.leave() }
                        while let chunk = try? pipe.fileHandleForReading.read(upToCount: 8192), !chunk.isEmpty {
                            buffer.append(chunk)
                        }
                    }
                }
                let timedOut = completed.wait(timeout: .now() + timeout) == .timedOut
                if timedOut {
                    if process.isRunning { process.terminate() }
                    if completed.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                        _ = completed.wait(timeout: .now() + 1)
                    }
                }
                let drained = readers.wait(timeout: .now() + 1) == .success
                let (text, oversized) = output.result()
                if timedOut || !drained {
                    continuation.resume(throwing: CommandError.timedOut)
                } else if oversized || errors.result().1 {
                    continuation.resume(throwing: CommandError.outputTooLarge)
                } else {
                    continuation.resume(returning: CommandResult(output: text, exitCode: process.terminationStatus))
                }
            }
        }
    }
}
