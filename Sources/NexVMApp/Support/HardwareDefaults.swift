import Foundation
import NexVMCore

/// User-chosen starting values for the creation wizard (Settings → Hardware Defaults / Storage).
/// Stored in UserDefaults; always clamped to what the host allows.
enum HardwareDefaults {
    static let useRecommendedKey = "defaults.useRecommended"
    static let cpuKey = "defaults.cpuCount"
    static let memoryKey = "defaults.memoryMiB"
    static let diskKey = "defaults.diskGiB"

    static func resolved(for guest: GuestOS, host: HostResources, store: UserDefaults = .standard) -> ResourceRecommendation {
        let rec = ResourcePolicy.recommendation(for: guest, host: host)
        guard store.object(forKey: useRecommendedKey) as? Bool == false else { return rec }
        let cpu = store.integer(forKey: cpuKey), mem = store.integer(forKey: memoryKey), disk = store.integer(forKey: diskKey)
        return ResourceRecommendation(
            cpuCount: cpu > 0 ? min(max(1, cpu), ResourcePolicy.maxCPUCount(host: host)) : rec.cpuCount,
            memoryMiB: mem > 0 ? min(max(ResourcePolicy.minimumMemoryMiB, mem), ResourcePolicy.maxMemoryMiB(host: host)) : rec.memoryMiB,
            diskGiB: disk > 0 ? min(max(ResourcePolicy.minimumDiskGiB, disk), max(ResourcePolicy.minimumDiskGiB, host.availableDiskGiB)) : rec.diskGiB)
    }
}
