import Foundation

public struct QEMUInstallation: Equatable, Sendable {
    public var system: URL            // qemu-system-aarch64
    public var imageTool: URL?        // qemu-img
    public var firmwareCode: URL?     // edk2-aarch64-code.fd

    public init(system: URL, imageTool: URL? = nil, firmwareCode: URL? = nil) {
        self.system = system
        self.imageTool = imageTool
        self.firmwareCode = firmwareCode
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
            return QEMUInstallation(
                system: system.resolvingSymlinksInPath(),
                imageTool: fileManager.isExecutableFile(atPath: img.path) ? img : nil,
                firmwareCode: fileManager.isReadableFile(atPath: fw.path) ? fw : nil
            )
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
