import Foundation

public struct HostResources: Equatable, Sendable {
    public var physicalMemoryMiB: Int
    public var cpuCores: Int
    public var isAppleSilicon: Bool
    public var availableDiskGiB: Int

    public init(physicalMemoryMiB: Int, cpuCores: Int, isAppleSilicon: Bool, availableDiskGiB: Int) {
        self.physicalMemoryMiB = physicalMemoryMiB
        self.cpuCores = cpuCores
        self.isAppleSilicon = isAppleSilicon
        self.availableDiskGiB = availableDiskGiB
    }

    /// Reads the live host. `volume` selects the volume whose free space is reported.
    public static func current(volume: URL = FileManager.default.homeDirectoryForCurrentUser) -> HostResources {
        let info = ProcessInfo.processInfo
        let memMiB = Int(info.physicalMemory / (1024 * 1024))
        #if arch(arm64)
        let arm = true
        #else
        let arm = false
        #endif
        // The volume may not exist yet (new library): measure its nearest existing ancestor.
        var probe = volume
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" {
            probe = probe.deletingLastPathComponent()
        }
        let freeBytes = (try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? 0
        return HostResources(
            physicalMemoryMiB: memMiB,
            cpuCores: info.activeProcessorCount,
            isAppleSilicon: arm,
            availableDiskGiB: Int(freeBytes / (1024 * 1024 * 1024))
        )
    }
}

public struct ResourceRecommendation: Equatable, Sendable {
    public var cpuCount: Int
    public var memoryMiB: Int
    public var diskGiB: Int
}

public enum ResourcePolicy {
    public static let minimumMemoryMiB = 1024
    public static let minimumDiskGiB = 8

    /// Hard upper bound for guest RAM: half of host RAM, so macOS stays responsive.
    public static func maxMemoryMiB(host: HostResources) -> Int { host.physicalMemoryMiB / 2 }

    /// Hard upper bound for vCPUs: leave two cores to the host (at least one vCPU).
    public static func maxCPUCount(host: HostResources) -> Int { max(1, host.cpuCores - 2) }

    public static func recommendation(for guest: GuestOS, host: HostResources) -> ResourceRecommendation {
        let (memWanted, cpuWanted, diskWanted): (Int, Int, Int) = switch guest {
        case .windows11ARM64: (4096, 4, 64)
        case .linuxARM64: (2048, 2, 32)
        }
        // Keep recommendations inside the limits and leave room on disk.
        let disk = max(ResourcePolicy.minimumDiskGiB, min(diskWanted, host.availableDiskGiB / 2))
        return ResourceRecommendation(
            cpuCount: min(cpuWanted, maxCPUCount(host: host)),
            memoryMiB: min(memWanted, maxMemoryMiB(host: host)),
            diskGiB: disk
        )
    }
}

public enum ConfigurationIssue: Equatable, Sendable, CustomStringConvertible {
    case emptyName
    case nameTooLong(max: Int)
    case unsupportedHost
    case memoryTooLow(minMiB: Int)
    case memoryExceedsLimit(maxMiB: Int)
    case cpuOutOfRange(max: Int)
    case noDisk
    case diskTooSmall(minGiB: Int)
    case insufficientHostDisk(neededGiB: Int, availableGiB: Int)
    case absoluteDiskPath(String)

    public var description: String {
        switch self {
        case .emptyName: "VM name must not be empty."
        case .nameTooLong(let max): "VM name must be at most \(max) characters."
        case .unsupportedHost: "NexVM requires an Apple Silicon Mac."
        case .memoryTooLow(let m): "Memory must be at least \(m) MiB."
        case .memoryExceedsLimit(let m): "Memory must not exceed \(m) MiB (half of host RAM)."
        case .cpuOutOfRange(let m): "CPU count must be between 1 and \(m)."
        case .noDisk: "At least one disk is required."
        case .diskTooSmall(let m): "Disk must be at least \(m) GiB."
        case .insufficientHostDisk(let n, let a): "Disks need \(n) GiB but only \(a) GiB are free."
        case .absoluteDiskPath(let p): "Disk path must be relative to the VM bundle: \(p)"
        }
    }
}

public enum ConfigurationValidator {
    public static let maxNameLength = 64

    public static func validate(_ config: VMConfiguration, host: HostResources) -> [ConfigurationIssue] {
        var issues: [ConfigurationIssue] = []
        let name = config.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { issues.append(.emptyName) }
        if name.count > maxNameLength { issues.append(.nameTooLong(max: maxNameLength)) }
        if !host.isAppleSilicon { issues.append(.unsupportedHost) }

        if config.memoryMiB < ResourcePolicy.minimumMemoryMiB {
            issues.append(.memoryTooLow(minMiB: ResourcePolicy.minimumMemoryMiB))
        }
        let maxMem = ResourcePolicy.maxMemoryMiB(host: host)
        if config.memoryMiB > maxMem { issues.append(.memoryExceedsLimit(maxMiB: maxMem)) }

        let maxCPU = ResourcePolicy.maxCPUCount(host: host)
        if config.cpuCount < 1 || config.cpuCount > maxCPU { issues.append(.cpuOutOfRange(max: maxCPU)) }

        if config.disks.isEmpty { issues.append(.noDisk) }
        for disk in config.disks {
            if disk.sizeGiB < ResourcePolicy.minimumDiskGiB {
                issues.append(.diskTooSmall(minGiB: ResourcePolicy.minimumDiskGiB))
            }
            if disk.relativePath.hasPrefix("/") { issues.append(.absoluteDiskPath(disk.relativePath)) }
        }
        let total = config.disks.reduce(0) { $0 + $1.sizeGiB }
        if total > host.availableDiskGiB {
            issues.append(.insufficientHostDisk(neededGiB: total, availableGiB: host.availableDiskGiB))
        }
        return issues
    }
}
