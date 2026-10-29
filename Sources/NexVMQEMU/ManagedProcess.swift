import Foundation
import NexVMEngine

/// Owns exactly one child process started by NexVM. Signals are sent only to that
/// pid, never by name, so other applications' QEMU processes are never touched.
public final class ManagedProcess: @unchecked Sendable {
    private let process = Process()
    private let lock = NSLock()
    private var exitCode: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []
    private var logHandle: FileHandle?

    public init() {}

    public var processIdentifier: Int32 { process.processIdentifier }
    public var isRunning: Bool { process.isRunning }

    /// Starts the process with structured arguments. stdout/stderr are appended to `logURL` (0600).
    public func launch(executable: URL, arguments: [String], logURL: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: logURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
        }
        let handle = try FileHandle(forWritingTo: logURL)
        try handle.seekToEnd()
        logHandle = handle

        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { [weak self] p in self?.finish(p.terminationStatus) }
        do { try process.run() } catch {
            try? handle.close()
            throw EngineError.launchFailed(error.localizedDescription)
        }
    }

    private func finish(_ code: Int32) {
        lock.lock()
        exitCode = code
        let pending = waiters
        waiters = []
        lock.unlock()
        try? logHandle?.close()
        pending.forEach { $0.resume(returning: code) }
    }

    public func waitForExit() async -> Int32 {
        await withCheckedContinuation { cont in
            lock.lock()
            if let code = exitCode { lock.unlock(); cont.resume(returning: code) } else {
                waiters.append(cont)
                lock.unlock()
            }
        }
    }

    /// SIGTERM, then SIGKILL after `grace` seconds. Returns the exit status.
    @discardableResult
    public func terminate(grace: TimeInterval = 5) async -> Int32 {
        guard process.isRunning else { return await waitForExit() }
        let pid = process.processIdentifier
        process.terminate()  // SIGTERM to our child
        let killer = Task {
            try? await Task.sleep(for: .seconds(grace))
            if !Task.isCancelled, kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
        let code = await waitForExit()
        killer.cancel()
        return code
    }

    /// Waits up to `timeout`; returns nil if the process is still running.
    public func waitForExit(timeout: TimeInterval) async -> Int32? {
        // Poll: a continuation-based wait cannot be cancelled, so racing it would block until exit.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let code = currentExitCode() { return code }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return currentExitCode()
    }

    private func currentExitCode() -> Int32? { lock.withLock { exitCode } }
}
