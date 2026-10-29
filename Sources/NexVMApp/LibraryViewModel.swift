import Foundation
import Observation
import NexVMCore
import NexVMStorage
import NexVMDiagnostics
import NexVMEngine
import NexVMQEMU

struct VMItem: Identifiable, Equatable {
    let bundle: VMBundle
    let configuration: VMConfiguration
    var id: UUID { configuration.id }
}

struct NewVMRequest {
    var name: String
    var guest: GuestOS
    var cpuCount: Int
    var memoryMiB: Int
    var diskGiB: Int
    var isoPath: String?
}

@MainActor
@Observable
final class LibraryViewModel {
    private(set) var items: [VMItem] = []
    private(set) var failedBundles: [String] = []
    var errorMessage: String?
    private(set) var states: [UUID: VMRuntimeState] = [:]
    let host: HostResources
    /// nil when QEMU/firmware is not found; start buttons are disabled then.
    let engine: QEMUEngine?
    let qemuAvailable: Bool

    private let library: VMLibrary
    private let logger: StructuredLogger

    init(library: VMLibrary = VMLibrary(root: VMLibrary.defaultRoot)) {
        self.library = library
        self.host = HostResources.current(volume: library.root)
        let logURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/NexVM/nexvm.log")
        self.logger = StructuredLogger(fileURL: logURL)
        if let install = QEMUBinaryLocator.locate(), install.firmwareCode != nil, install.firmwareVarsTemplate != nil {
            self.engine = QEMUEngine(installation: install, logger: logger)
            self.qemuAvailable = true
        } else {
            self.engine = nil
            self.qemuAvailable = false
        }
        reload()
        startPolling()
    }

    func state(of item: VMItem) -> VMRuntimeState { states[item.id] ?? .stopped }

    private func startPolling() {
        guard let engine else { return }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                for item in self.items {
                    let s = await engine.state(of: item.id)
                    if self.states[item.id] != s { self.states[item.id] = s }
                }
            }
        }
    }

    func start(_ item: VMItem) {
        guard let engine else { errorMessage = L("error.noqemu"); return }
        states[item.id] = .starting
        Task {
            do { try await engine.start(item.configuration, bundleURL: item.bundle.url) } catch {
                errorMessage = "\(error)"
            }
            states[item.id] = await engine.state(of: item.id)
        }
    }

    func requestShutdown(_ item: VMItem) {
        guard let engine else { return }
        Task { do { try await engine.requestShutdown(vmID: item.id) } catch { errorMessage = "\(error)" } }
    }

    func forceStop(_ item: VMItem) {
        guard let engine else { return }
        Task { do { try await engine.forceStop(vmID: item.id) } catch { errorMessage = "\(error)" } }
    }

    func reload() {
        do {
            let listing = try library.list()
            items = listing.bundles.compactMap { b in
                (try? library.load(b)).map { VMItem(bundle: b, configuration: $0) }
            }
            failedBundles = listing.failures.map { $0.url.lastPathComponent }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func recommendation(for guest: GuestOS) -> ResourceRecommendation {
        ResourcePolicy.recommendation(for: guest, host: host)
    }

    /// Creates the bundle, config and an empty sparse disk. Does not start anything.
    @discardableResult
    func create(_ r: NewVMRequest) -> Bool {
        let disk = DiskConfiguration(
            relativePath: "disks/main.img", sizeGiB: r.diskGiB, format: .raw,
            interface: r.guest == .windows11ARM64 ? .nvme : .virtioBlk)
        let config = VMConfiguration(
            name: r.name.trimmingCharacters(in: .whitespacesAndNewlines), guest: r.guest,
            cpuCount: r.cpuCount, memoryMiB: r.memoryMiB, disks: [disk],
            installMedia: r.isoPath.map(InstallMedia.init(path:)))

        let issues = ConfigurationValidator.validate(config, host: host)
        guard issues.isEmpty else {
            errorMessage = issues.map(\.description).joined(separator: "\n")
            return false
        }
        if let iso = r.isoPath {
            do { try ISOValidator.validate(path: iso) } catch {
                errorMessage = "ISO check failed: \(error)"
                return false
            }
        }
        do {
            let bundle = try library.create(config)
            do { try DiskImageCreator.createSparseRaw(in: bundle, relativePath: disk.relativePath, sizeGiB: disk.sizeGiB) } catch {
                // Roll back the bundle we just created (confirmed by construction: it is ours).
                try? library.deleteData(of: bundle, confirmation: DeletionConfirmation(confirmingDeletionOf: config.id))
                throw error
            }
            let id = config.id
            Task { await logger.log(.info, "library", "created VM", vmID: id) }
            reload()
            return true
        } catch {
            errorMessage = "\(error)"
            return false
        }
    }

    func remove(_ item: VMItem) {
        do {
            try library.removeFromLibrary(item.bundle)
            reload()
        } catch { errorMessage = "\(error)" }
    }

    func deleteData(_ item: VMItem) {
        do {
            try library.deleteData(of: item.bundle, confirmation: DeletionConfirmation(confirmingDeletionOf: item.id))
            reload()
        } catch { errorMessage = "\(error)" }
    }
}
