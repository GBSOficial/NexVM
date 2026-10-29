import Foundation
import NexVMCore
import NexVMEngine
import NexVMStorage
import NexVMDiagnostics

/// QEMU/HVF backend. One child process per VM, tracked by VM id; only processes this
/// engine launched are ever signalled.
public actor QEMUEngine: VirtualMachineEngine {
    private struct Session {
        let process: ManagedProcess
        let lock: VMLock
        let socketURL: URL
        var qmp: QMPClient?
        var state: VMRuntimeState
        var shutdownRequested = false
    }

    private let installation: QEMUInstallation
    private let options: QEMUBuildOptions
    private let logger: StructuredLogger?
    private var sessions: [UUID: Session] = [:]

    public init(installation: QEMUInstallation, options: QEMUBuildOptions = QEMUBuildOptions(), logger: StructuredLogger? = nil) {
        self.installation = installation
        self.options = options
        self.logger = logger
    }

    public func state(of vmID: UUID) -> VMRuntimeState { sessions[vmID]?.state ?? .stopped }

    public func start(_ c: VMConfiguration, bundleURL: URL) async throws {
        if let s = sessions[c.id], s.state != .stopped {
            if case .error = s.state {} else { throw EngineError.alreadyRunning(c.id) }
        }
        guard let code = installation.firmwareCode, let template = installation.firmwareVarsTemplate else {
            throw EngineError.backendUnavailable("UEFI firmware (edk2) not found next to QEMU")
        }
        let bundle = VMBundle(url: bundleURL)
        let lock: VMLock
        do { lock = try VMLock(bundleURL: bundleURL) } catch { throw EngineError.alreadyRunning(c.id) }

        do {
            // Per-VM writable NVRAM, created once from the template and kept across boots.
            let vars = try PathValidator.resolve("metadata/vars.fd", under: bundleURL)
            if !FileManager.default.fileExists(atPath: vars.path) {
                try FileManager.default.copyItem(at: template, to: vars)
            }
            // sun_path is limited to ~104 bytes; keep the socket in a short private temp dir.
            let socketDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("nexvm-\(c.id.uuidString.prefix(8))")
            try FileManager.default.createDirectory(at: socketDir, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let socket = socketDir.appendingPathComponent("qmp.sock")
            try? FileManager.default.removeItem(at: socket)  // stale socket of a previous run of this VM

            let spec = try QEMUCommandBuilder(installation: installation).build(
                configuration: c, bundle: bundle, firmware: QEMUFirmware(code: code, vars: vars),
                qmpSocket: socket, options: options)
            let process = ManagedProcess()
            sessions[c.id] = Session(process: process, lock: lock, socketURL: socket, qmp: nil, state: .starting)
            await logger?.log(.info, "qemu", "launching VM", vmID: c.id)
            try process.launch(executable: spec.executable, arguments: spec.arguments,
                               logURL: bundle.logsURL.appendingPathComponent("qemu.log"))

            let id = c.id
            Task { [weak self] in
                let code = await process.waitForExit()
                await self?.processExited(id, code: code)
            }
            let client = try await QMPClient.connect(path: socket.path) { [weak self] name in
                Task { await self?.handleEvent(id, name) }
            }
            sessions[id]?.qmp = client
            if sessions[id]?.state == .starting { sessions[id]?.state = .running }
        } catch {
            if let s = sessions[c.id] { await s.process.terminate(grace: 2) }
            sessions[c.id] = nil
            lock.release()
            let tail = (try? String(contentsOf: bundle.logsURL.appendingPathComponent("qemu.log"), encoding: .utf8))
                .map { String($0.suffix(600)) } ?? ""
            await logger?.log(.error, "qemu", "start failed: \(error) \(tail)", vmID: c.id)
            if tail.isEmpty { throw error }
            throw EngineError.launchFailed("\(error); qemu.log: \(tail)")
        }
    }

    public func requestShutdown(vmID: UUID) async throws {
        guard let s = sessions[vmID], s.state == .running, let qmp = s.qmp else { throw EngineError.notRunning(vmID) }
        sessions[vmID]?.state = .stopping
        sessions[vmID]?.shutdownRequested = true
        let r = await qmp.send(.systemPowerdown)
        if case .failure(_, let d, _) = r {
            sessions[vmID]?.state = .running
            throw EngineError.launchFailed("powerdown rejected: \(d)")
        }
    }

    public func forceStop(vmID: UUID) async throws {
        guard let s = sessions[vmID], s.state != .stopped else { throw EngineError.notRunning(vmID) }
        sessions[vmID]?.shutdownRequested = true
        sessions[vmID]?.state = .stopping
        _ = await s.process.terminate(grace: 5)
    }

    /// Waits until the VM reaches `.stopped` (or `.error`), up to `timeout` seconds.
    public func waitUntilStopped(vmID: UUID, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch sessions[vmID]?.state ?? .stopped {
            case .stopped, .error: return true
            default: try? await Task.sleep(for: .milliseconds(100))
            }
        }
        return false
    }

    private func handleEvent(_ id: UUID, _ name: String) async {
        await logger?.log(.debug, "qmp", "event \(name)", vmID: id)
    }

    private func processExited(_ id: UUID, code: Int32) async {
        guard let s = sessions[id] else { return }
        s.qmp?.close()
        try? FileManager.default.removeItem(at: s.socketURL.deletingLastPathComponent())
        let expected = s.shutdownRequested || code == 0
        sessions[id]?.state = expected ? .stopped : .error("QEMU exited unexpectedly (status \(code))")
        s.lock.release()
        await logger?.log(expected ? .info : .error, "qemu", "process exited status \(code)", vmID: id)
        if expected { sessions[id] = nil }
    }
}
