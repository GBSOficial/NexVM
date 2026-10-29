import Foundation
import Darwin
import NexVMEngine

/// Minimal QMP client over a unix socket. One connection, request/response by id,
/// events delivered to `onEvent`.
public final class QMPClient: @unchecked Sendable {
    private let fd: Int32
    private let lock = NSLock()
    private var pending: [String: CheckedContinuation<QMPMessage, Never>] = [:]
    private var nextID = 0
    private var closed = false
    private var greeting: CheckedContinuation<String, Error>?
    private let onEvent: @Sendable (String) -> Void
    private var readTask: Task<Void, Never>?

    /// Connects with retries (QEMU creates the socket shortly after launch).
    public static func connect(path: String, timeout: TimeInterval = 10,
                               onEvent: @escaping @Sendable (String) -> Void = { _ in }) async throws -> QMPClient {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let fd = openSocket(path) {
                let c = QMPClient(fd: fd, onEvent: onEvent)
                do { try await c.handshake(timeout: max(1, deadline.timeIntervalSinceNow)); return c } catch {
                    c.close(); throw error
                }
            }
            if Date() > deadline { throw EngineError.timedOut("QMP socket \(path)") }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    private static func openSocket(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { Darwin.close(fd); return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in
            bytes.withUnsafeBytes { dst.copyMemory(from: $0) }
        }
        let ok = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if ok != 0 { Darwin.close(fd); return nil }
        return fd
    }

    private init(fd: Int32, onEvent: @escaping @Sendable (String) -> Void) {
        self.fd = fd
        self.onEvent = onEvent
    }

    private func handshake(timeout: TimeInterval) async throws {
        readTask = Task.detached { [self] in readLoop() }
        _ = try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask { try await withCheckedThrowingContinuation { c in self.setGreeting(c) } }
            group.addTask { try await Task.sleep(for: .seconds(timeout)); throw EngineError.timedOut("QMP greeting") }
            let v = try await group.next() ?? ""
            group.cancelAll()
            return v
        }
        let r = await send(.capabilities)
        guard case .success = r else { throw EngineError.launchFailed("qmp_capabilities rejected: \(r)") }
    }

    private func setGreeting(_ c: CheckedContinuation<String, Error>) {
        lock.withLock { greeting = c }
    }

    public func send(_ command: QMP.Command) async -> QMPMessage {
        let id: String = lock.withLock { nextID += 1; return String(nextID) }
        return await withCheckedContinuation { cont in
            let dead = lock.withLock { () -> Bool in
                if closed { return true }
                pending[id] = cont
                return false
            }
            if dead { cont.resume(returning: .failure(errorClass: "Closed", description: "connection closed", id: id)); return }
            let data = QMP.encode(command, id: id)
            let written = data.withUnsafeBytes { Darwin.write(fd, $0.baseAddress, data.count) }
            if written != data.count, let c = lock.withLock({ pending.removeValue(forKey: id) }) {
                c.resume(returning: .failure(errorClass: "WriteFailed", description: "errno \(errno)", id: id))
            }
        }
    }

    public func close() {
        let (conts, g): ([CheckedContinuation<QMPMessage, Never>], CheckedContinuation<String, Error>?) = lock.withLock {
            if closed { return ([], nil) }
            closed = true
            let c = Array(pending.values); pending = [:]
            let g = greeting; greeting = nil
            return (c, g)
        }
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
        conts.forEach { $0.resume(returning: .failure(errorClass: "Closed", description: "connection closed", id: nil)) }
        g?.resume(throwing: EngineError.launchFailed("QMP closed before greeting"))
    }

    private func readLoop() {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = Darwin.read(fd, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(chunk, count: n)
            while let nl = buffer.firstIndex(of: 0x0A) {
                let line = buffer.subdata(in: buffer.startIndex..<nl)
                buffer.removeSubrange(buffer.startIndex...nl)
                if !line.isEmpty { handle(line) }
            }
        }
        close()
    }

    private func handle(_ line: Data) {
        guard let msg = try? QMP.parse(line) else { return }
        switch msg {
        case .greeting(let v):
            lock.withLock { let g = greeting; greeting = nil; return g }?.resume(returning: v)
        case .event(let name):
            onEvent(name)
        case .success(let id), .failure(_, _, let id):
            if let id, let c = lock.withLock({ pending.removeValue(forKey: id) }) { c.resume(returning: msg) }
        }
    }
}
