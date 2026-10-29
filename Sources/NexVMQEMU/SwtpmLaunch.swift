import Foundation
import NexVMEngine

/// Builds the argv for a per-VM `swtpm` TPM 2.0 emulator. QEMU connects to its control socket
/// (`-chardev socket` + `-tpmdev emulator`, see QEMUCommandBuilder). Nothing listens on TCP.
public enum SwtpmLaunch {
    public static func arguments(stateDir: URL, controlSocket: URL, logFile: URL) throws -> [String] {
        // swtpm option values are comma-separated and have no escaping, so refuse paths that would split them.
        for url in [stateDir, controlSocket, logFile] where url.path.contains(",") {
            throw EngineError.launchFailed("TPM paths must not contain commas: \(url.path)")
        }
        return [
            "socket",
            "--tpm2",
            "--tpmstate", "dir=\(stateDir.path)",
            "--ctrl", "type=unixio,path=\(controlSocket.path)",
            "--log", "file=\(logFile.path),level=1",
            "--terminate",   // exit when QEMU disconnects, so no TPM process outlives its VM
        ]
    }
}
