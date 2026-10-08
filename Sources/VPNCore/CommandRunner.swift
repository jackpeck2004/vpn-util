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

private final class PipeReader {
    private let queue = DispatchQueue(label: "VPNUtility.pipe", qos: .utility)
    private let source: DispatchSourceRead
    private let descriptor: Int32
    private let output = OutputBuffer()
    private var stopped = false

    init(_ pipe: Pipe) throws {
        let handle = pipe.fileHandleForReading
        descriptor = handle.fileDescriptor
        let flags = fcntl(descriptor, F_GETFL)
        guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) >= 0 else {
            throw CommandError.failed
        }
        source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { try? handle.close() }
        source.resume()
    }

    deinit { source.cancel() }

    private func drain() {
        guard !stopped else { return }
        var bytes = [UInt8](repeating: 0, count: 8192)
        // Bound each callback even if a descendant writes continuously.
        for _ in 0..<32 {
            let count = bytes.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                output.append(Data(bytes.prefix(count)))
            } else if count == 0 || (count < 0 && errno != EAGAIN && errno != EINTR) {
                stop()
                break
            } else if errno == EAGAIN {
                break
            }
        }
    }

    private func stop() {
        stopped = true
        source.cancel()
    }

    func finish() -> (String, Bool) {
        queue.sync {
            drain()
            stop()
            return output.result()
        }
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
                let output: PipeReader
                let errors: PipeReader
                do {
                    output = try PipeReader(stdout)
                    errors = try PipeReader(stderr)
                    try process.run()
                } catch {
                    continuation.resume(throwing: CommandError.failed)
                    return
                }

                let timedOut = completed.wait(timeout: .now() + timeout) == .timedOut
                if timedOut {
                    if process.isRunning { process.terminate() }
                    if completed.wait(timeout: .now() + 0.5) == .timedOut, process.isRunning {
                        kill(process.processIdentifier, SIGKILL)
                        _ = completed.wait(timeout: .now() + 1)
                    }
                }
                let (text, oversized) = output.finish()
                let oversizedErrors = errors.finish().1
                if timedOut {
                    continuation.resume(throwing: CommandError.timedOut)
                } else if oversized || oversizedErrors {
                    continuation.resume(throwing: CommandError.outputTooLarge)
                } else {
                    continuation.resume(returning: CommandResult(output: text, exitCode: process.terminationStatus))
                }
            }
        }
    }
}
