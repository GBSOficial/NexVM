import Foundation
import AppKit
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
    var firmware: FirmwareKind = .standard
}

/// UI-facing state. The QEMU lifecycle lives in `QEMUEngine` (an actor); this class only
/// mirrors its state on the main actor and forwards user intent.
@MainActor
@Observable
final class LibraryViewModel {
    private(set) var items: [VMItem] = []
    private(set) var failedBundles: [String] = []
    private(set) var states: [UUID: VMRuntimeState] = [:]
    private(set) var host: HostResources
    var errorMessage: String?
    var selection: UUID?
    var showingNewVM = false
    var pendingDeletion: VMItem?

    let libraryRoot: URL
    let logURL: URL
    let qemuPath: String?
    let qemuAvailable: Bool
    let swtpmAvailable: Bool
    let secureBootAvailable: Bool
    private let engine: QEMUEngine?
    private let library: VMLibrary
    private let logger: StructuredLogger

    init(library: VMLibrary = VMLibrary(root: VMLibrary.defaultRoot)) {
        self.library = library
        self.libraryRoot = library.root
        self.host = HostResources.current(volume: library.root)
        self.logURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/NexVM/nexvm.log")
        let logger = StructuredLogger(fileURL: logURL)
        self.logger = logger
        if let install = QEMUBinaryLocator.locate(), install.firmwareCode != nil, install.firmwareVarsTemplate != nil {
            self.engine = QEMUEngine(installation: install, logger: logger)
            self.qemuAvailable = true
            self.qemuPath = install.system.path
            self.swtpmAvailable = install.swtpm != nil
            self.secureBootAvailable = install.secureBootFirmware != nil
        } else {
            self.engine = nil
            self.qemuAvailable = false
            self.qemuPath = nil
            self.swtpmAvailable = false
            self.secureBootAvailable = false
        }
        reload()
        startPolling()
    }

    // MARK: Queries

    func item(_ id: UUID?) -> VMItem? { id.flatMap { id in items.first { $0.id == id } } }
    func state(of item: VMItem) -> VMRuntimeState { states[item.id] ?? .stopped }
    func state(of id: UUID) -> VMRuntimeState { states[id] ?? .stopped }

    var runningItems: [VMItem] { items.filter { !state(of: $0).isIdle } }

    static let embeddedDisplayKey = "display.embedded"
    /// Show the guest display inside NexVM (VNC) instead of QEMU's own window. Default: on.
    var embeddedDisplay: Bool { UserDefaults.standard.object(forKey: Self.embeddedDisplayKey) as? Bool ?? true }

    /// Unix socket path serving this VM's display, once it has been started with the embedded display.
    func displaySocketPath(for item: VMItem) async -> String? {
        await engine?.displaySocket(for: item.id)?.path
    }

    /// Why this VM cannot be started right now (missing tooling), or nil.
    func startBlocker(for config: VMConfiguration) -> String? {
        if !qemuAvailable { return L("error.noqemu") }
        if config.guest == .windows11ARM64 && !swtpmAvailable { return L("error.notpm") }
        if config.effectiveFirmware == .secureBoot && !secureBootAvailable { return L("error.nosecureboot") }
        return nil
    }

    func refreshHost() { host = HostResources.current(volume: libraryRoot) }

    /// Last lines of the VM's qemu.log (stdout/stderr of the QEMU process).
    func qemuLogTail(for item: VMItem, maxBytes: Int = 4000) -> String {
        let url = item.bundle.logsURL.appendingPathComponent("qemu.log")
        guard let h = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > UInt64(maxBytes) ? size - UInt64(maxBytes) : 0)
        return String(decoding: (try? h.readToEnd()) ?? Data(), as: UTF8.self)
    }

    func readAppLog() -> [LogEntry] {
        ((try? LogReader.read(fileURL: logURL)) ?? []).reversed()
    }

    // MARK: Library

    func reload() {
        do {
            let listing = try library.list()
            items = listing.bundles.compactMap { b in
                (try? library.load(b)).map { VMItem(bundle: b, configuration: $0) }
            }
            failedBundles = listing.failures.map { $0.url.lastPathComponent }
            if let sel = selection, !items.contains(where: { $0.id == sel }) { selection = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
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
            installMedia: r.isoPath.map(InstallMedia.init(path:)), firmware: r.firmware == .standard ? nil : r.firmware)

        refreshHost()
        let issues = ConfigurationValidator.validate(config, host: host)
        guard issues.isEmpty else {
            errorMessage = issues.map(\.description).joined(separator: "\n")
            return false
        }
        do {
            let bundle = try library.create(config)
            do { try DiskImageCreator.createSparseRaw(in: bundle, relativePath: disk.relativePath, sizeGiB: disk.sizeGiB) } catch {
                // Roll back the bundle we just created (it is ours by construction).
                try? library.deleteData(of: bundle, confirmation: DeletionConfirmation(confirmingDeletionOf: config.id))
                throw error
            }
            let id = config.id
            Task { await logger.log(.info, "library", "created VM", vmID: id) }
            reload()
            selection = config.id
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

    /// Detaches the install ISO so the VM boots from its disk. Only while the VM is stopped;
    /// the ISO file itself is never touched.
    func ejectInstallMedia(_ item: VMItem) {
        guard state(of: item).isIdle, item.configuration.installMedia != nil else { return }
        var config = item.configuration
        config.installMedia = nil
        do {
            try library.save(config, in: item.bundle)
            reload()
            Task { await logger.log(.info, "library", "install media ejected", vmID: item.id) }
        } catch { errorMessage = "\(error)" }
    }

    /// Changes the UEFI build of a stopped VM. Each kind keeps its own NVRAM file, so switching back and forth is safe.
    func setFirmware(_ kind: FirmwareKind, for item: VMItem) {
        guard state(of: item).isIdle, item.configuration.effectiveFirmware != kind else { return }
        var config = item.configuration
        config.firmware = kind == .standard ? nil : kind
        do { try library.save(config, in: item.bundle); reload() } catch { errorMessage = "\(error)" }
    }

    /// Chooses the NIC model of a stopped VM. nil in the config means "default for the guest".
    func setNetworkAdapter(_ adapter: NetworkAdapter, for item: VMItem) {
        let c = item.configuration
        guard state(of: item).isIdle, c.network.effectiveAdapter(for: c.guest) != adapter else { return }
        var config = c
        config.network.adapter = adapter == NetworkConfiguration().effectiveAdapter(for: c.guest) ? nil : adapter
        do { try library.save(config, in: item.bundle); reload() } catch { errorMessage = "\(error)" }
    }

    /// Attaches (or clears, with nil) the optional driver ISO of a stopped VM. The file is only referenced.
    func setDriverMedia(path: String?, for item: VMItem) {
        guard state(of: item).isIdle else { return }
        if let path {
            do { try ISOValidator.validate(path: path) } catch { errorMessage = L("error.driveriso"); return }
        }
        var config = item.configuration
        config.driverMedia = path.map(InstallMedia.init(path:))
        do { try library.save(config, in: item.bundle); reload() } catch { errorMessage = "\(error)" }
    }

    func revealInFinder(_ item: VMItem) { NSWorkspace.shared.activateFileViewerSelecting([item.bundle.url]) }
    func revealLibrary() {
        try? FileManager.default.createDirectory(at: libraryRoot, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([libraryRoot])
    }
    func revealLog() {
        if FileManager.default.fileExists(atPath: logURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logURL])
        } else {
            NSWorkspace.shared.open(logURL.deletingLastPathComponent())
        }
    }

    // MARK: Lifecycle (forwarded to the engine)

    func start(_ item: VMItem) {
        guard let engine else { errorMessage = L("error.noqemu"); return }
        guard state(of: item).isIdle else { return }
        if let blocker = startBlocker(for: item.configuration) { errorMessage = blocker; return }
        selection = item.id   // keeps the Virtual Machine menu pointed at the VM being started
        states[item.id] = .starting
        Task {
            await engine.setEmbeddedDisplay(embeddedDisplay)
            do { try await engine.start(item.configuration, bundleURL: item.bundle.url) } catch {
                errorMessage = "\(error)"
            }
            states[item.id] = await engine.state(of: item.id)
        }
    }

    func requestShutdown(_ item: VMItem) { perform { try await $0.requestShutdown(vmID: item.id) } }
    func restart(_ item: VMItem) { perform { try await $0.restart(vmID: item.id) } }
    func forceStop(_ item: VMItem) { perform { try await $0.forceStop(vmID: item.id) } }

    private func perform(_ op: @escaping @Sendable (QEMUEngine) async throws -> Void) {
        guard let engine else { return }
        Task { do { try await op(engine) } catch { errorMessage = "\(error)" } }
    }

    /// Used at quit time: force-stops every VM this app started and waits for them.
    func stopAll() async {
        guard let engine else { return }
        for id in await engine.activeVMIDs() {
            try? await engine.forceStop(vmID: id)
            _ = await engine.waitUntilStopped(vmID: id, timeout: 10)
        }
        await logger.close()
    }

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
}
