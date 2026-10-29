import Foundation

/// UEFI build with Secure Boot, e.g. Debian's AAVMF (`AAVMF_CODE.secboot.fd` + `AAVMF_VARS.ms.fd`).
public struct SecureBootFirmware: Equatable, Sendable {
    public var code: URL
    public var varsTemplate: URL
    public init(code: URL, varsTemplate: URL) { self.code = code; self.varsTemplate = varsTemplate }
}

public struct QEMUInstallation: Equatable, Sendable {
    public var system: URL            // qemu-system-aarch64
    public var imageTool: URL?        // qemu-img
    public var firmwareCode: URL?     // edk2-aarch64-code.fd
    public var firmwareVarsTemplate: URL?  // edk2-arm-vars.fd (copied per VM)
    public var swtpm: URL?            // TPM 2.0 emulator; required for Windows 11 guests
    public var secureBootFirmware: SecureBootFirmware?

    public init(system: URL, imageTool: URL? = nil, firmwareCode: URL? = nil, firmwareVarsTemplate: URL? = nil, swtpm: URL? = nil,
                secureBootFirmware: SecureBootFirmware? = nil) {
        self.system = system
        self.imageTool = imageTool
        self.firmwareCode = firmwareCode
        self.firmwareVarsTemplate = firmwareVarsTemplate
        self.swtpm = swtpm
        self.secureBootFirmware = secureBootFirmware
    }
}

public enum QEMUBinaryLocator {
    public static let defaultSearchDirectories = [
        "/path/to/tools/homebrew/bin",
        "/opt/homebrew/bin",
        "/usr/local/bin",
    ]

    /// Looks for an existing QEMU install. Never installs or modifies anything.
    /// `explicit` (e.g. a user preference) wins over the search directories.
    public static func locate(
        explicit: URL? = nil,
        searchDirectories: [String] = defaultSearchDirectories,
        firmwareDirectories: [String]? = nil,
        fileManager: FileManager = .default
    ) -> QEMUInstallation? {
        var candidates: [URL] = []
        if let explicit { candidates.append(explicit) }
        candidates += searchDirectories.map { URL(fileURLWithPath: $0).appendingPathComponent("qemu-system-aarch64") }

        for system in candidates where fileManager.isExecutableFile(atPath: system.path) {
            let bin = system.deletingLastPathComponent()
            let img = bin.appendingPathComponent("qemu-img")
            let prefix = bin.deletingLastPathComponent()
            let fw = prefix.appendingPathComponent("share/qemu/edk2-aarch64-code.fd")
            let vars = prefix.appendingPathComponent("share/qemu/edk2-arm-vars.fd")
            let tpm = bin.appendingPathComponent("swtpm")
            return QEMUInstallation(
                system: system.resolvingSymlinksInPath(),
                imageTool: fileManager.isExecutableFile(atPath: img.path) ? img : nil,
                firmwareCode: fileManager.isReadableFile(atPath: fw.path) ? fw : nil,
                firmwareVarsTemplate: fileManager.isReadableFile(atPath: vars.path) ? vars : nil,
                swtpm: fileManager.isExecutableFile(atPath: tpm.path) ? tpm : nil,
                secureBootFirmware: locateSecureBootFirmware(
                    in: firmwareDirectories ?? defaultFirmwareDirectories(qemuPrefix: prefix), fileManager: fileManager)
            )
        }
        return nil
    }

    /// Where NexVM looks for a Secure Boot UEFI build: `$NEXVM_FIRMWARE_DIR`, the QEMU prefix
    /// (`share/nexvm/firmware`) and `~/Library/Application Support/NexVM/Firmware`.
    public static func defaultFirmwareDirectories(qemuPrefix: URL) -> [String] {
        var dirs: [String] = []
        if let env = ProcessInfo.processInfo.environment["NEXVM_FIRMWARE_DIR"], env.hasPrefix("/") { dirs.append(env) }
        dirs.append(qemuPrefix.appendingPathComponent("share/nexvm/firmware").path)
        dirs.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/NexVM/Firmware").path)
        return dirs
    }

    /// Finds `AAVMF_CODE.secboot.fd` + `AAVMF_VARS.ms.fd` (Debian naming), directly in a directory or in its `AAVMF/` subfolder.
    public static func locateSecureBootFirmware(in directories: [String], fileManager: FileManager = .default) -> SecureBootFirmware? {
        for dir in directories {
            for base in [URL(fileURLWithPath: dir), URL(fileURLWithPath: dir).appendingPathComponent("AAVMF")] {
                let code = base.appendingPathComponent("AAVMF_CODE.secboot.fd")
                let vars = base.appendingPathComponent("AAVMF_VARS.ms.fd")
                if fileManager.isReadableFile(atPath: code.path), fileManager.isReadableFile(atPath: vars.path) {
                    return SecureBootFirmware(code: code, varsTemplate: vars)
                }
            }
        }
        return nil
    }

    /// Extracts "11.1.2" from `QEMU emulator version 11.1.2 (...)`.
    public static func parseVersion(_ output: String) -> String? {
        guard let line = output.split(separator: "\n").first(where: { $0.contains("QEMU emulator version") }),
              let r = line.range(of: "version ") else { return nil }
        let rest = line[r.upperBound...]
        return rest.split(whereSeparator: { $0 == " " || $0 == "(" }).first.map(String.init)
    }
}
