import Foundation

public enum GuestOS: String, Codable, Sendable, CaseIterable {
    case windows11ARM64
    case linuxARM64
}

public enum CPUArchitecture: String, Codable, Sendable {
    case arm64
}

public enum BackendKind: String, Codable, Sendable {
    case qemu
}

public enum DiskFormat: String, Codable, Sendable {
    case raw
    case qcow2
}

public enum DiskInterface: String, Codable, Sendable {
    case virtioBlk
    case nvme
}

public enum NetworkMode: String, Codable, Sendable {
    /// User-mode (SLIRP) NAT. No host ports are opened.
    case userNAT
}

public struct DiskConfiguration: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    /// Path relative to the VM bundle root. Never absolute.
    public var relativePath: String
    public var sizeGiB: Int
    public var format: DiskFormat
    public var interface: DiskInterface

    public init(id: UUID = UUID(), relativePath: String, sizeGiB: Int, format: DiskFormat, interface: DiskInterface) {
        self.id = id
        self.relativePath = relativePath
        self.sizeGiB = sizeGiB
        self.format = format
        self.interface = interface
    }
}

public struct NetworkConfiguration: Codable, Equatable, Sendable {
    public var mode: NetworkMode
    public init(mode: NetworkMode = .userNAT) { self.mode = mode }
}

public struct InstallMedia: Codable, Equatable, Sendable {
    /// Absolute path to a user-supplied ISO. The file is referenced, never copied or modified.
    public var path: String
    public init(path: String) { self.path = path }
}

public struct VMConfiguration: Codable, Equatable, Sendable, Identifiable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var id: UUID
    public var name: String
    public var guest: GuestOS
    public var architecture: CPUArchitecture
    public var backend: BackendKind
    public var cpuCount: Int
    public var memoryMiB: Int
    public var disks: [DiskConfiguration]
    public var network: NetworkConfiguration
    public var installMedia: InstallMedia?
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        guest: GuestOS,
        cpuCount: Int,
        memoryMiB: Int,
        disks: [DiskConfiguration],
        network: NetworkConfiguration = NetworkConfiguration(),
        installMedia: InstallMedia? = nil,
        now: Date = Date()
    ) {
        self.schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.name = name
        self.guest = guest
        self.architecture = .arm64
        self.backend = .qemu
        self.cpuCount = cpuCount
        self.memoryMiB = memoryMiB
        self.disks = disks
        self.network = network
        self.installMedia = installMedia
        // JSON stores whole seconds (ISO 8601); keep the in-memory value identical to the stored one.
        let whole = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        self.createdAt = whole
        self.updatedAt = whole
    }
}

public enum NexVMJSON {
    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
