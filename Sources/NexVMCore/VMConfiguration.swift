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

/// Which UEFI build a VM boots with. The NVRAM variable store is tied to the build, so each kind
/// keeps its own variable file in the bundle.
public enum FirmwareKind: String, Codable, Sendable, CaseIterable {
    case standard      // QEMU's stock edk2 (no Secure Boot on aarch64)
    case secureBoot    // edk2 with Secure Boot and Microsoft keys enrolled (needed by Windows 11 Setup)
}

public enum NetworkMode: String, Codable, Sendable {
    /// User-mode (SLIRP) NAT. No host ports are opened.
    case userNAT
}

/// Virtual NIC model. Windows has an inbox driver for e1000e only; virtio-net needs the
/// user-supplied virtio-win drivers.
public enum NetworkAdapter: String, Codable, Sendable, CaseIterable {
    case e1000e
    case virtio
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
    /// Optional so older configs still load (nil = default per guest, see `effectiveAdapter(for:)`).
    public var adapter: NetworkAdapter?
    public init(mode: NetworkMode = .userNAT, adapter: NetworkAdapter? = nil) {
        self.mode = mode
        self.adapter = adapter
    }

    public func effectiveAdapter(for guest: GuestOS) -> NetworkAdapter {
        adapter ?? (guest == .windows11ARM64 ? .e1000e : .virtio)
    }
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
    /// Optional so configs written before this field existed still load (nil = standard).
    public var firmware: FirmwareKind?
    /// Optional second ISO (e.g. a user-supplied virtio-win.iso), attached read-only without boot priority.
    public var driverMedia: InstallMedia?
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
        firmware: FirmwareKind? = nil,
        driverMedia: InstallMedia? = nil,
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
        self.firmware = firmware
        self.driverMedia = driverMedia
        // JSON stores whole seconds (ISO 8601); keep the in-memory value identical to the stored one.
        let whole = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        self.createdAt = whole
        self.updatedAt = whole
    }
}

extension VMConfiguration {
    public var effectiveFirmware: FirmwareKind { firmware ?? .standard }
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
