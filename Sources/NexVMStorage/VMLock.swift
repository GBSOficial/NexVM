import Foundation
import Darwin

/// Exclusive advisory lock on a VM bundle (flock). Prevents two NexVM instances
/// (or two engines) from running the same VM. Released on deinit or process death.
public final class VMLock: @unchecked Sendable {
    private var fd: Int32

    public init(bundleURL: URL) throws {
        let path = bundleURL.appendingPathComponent(".lock").path
        let fd = open(path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw StorageError.io("cannot open lock file: errno \(errno)") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            throw StorageError.locked(bundleURL.lastPathComponent)
        }
        self.fd = fd
    }

    public func release() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    deinit { release() }
}
