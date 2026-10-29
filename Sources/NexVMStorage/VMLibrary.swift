import Foundation
import NexVMCore

public struct BundleManifest: Codable, Equatable, Sendable {
    public static let currentFormatVersion = 1
    public var formatVersion: Int
    public var vmID: UUID
    public var createdAt: Date
}

public struct VMBundle: Equatable, Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public var configURL: URL { url.appendingPathComponent("config.json") }
    public var manifestURL: URL { url.appendingPathComponent("manifest.json") }
    public var disksURL: URL { url.appendingPathComponent("disks") }
    public var logsURL: URL { url.appendingPathComponent("logs") }
    public var metadataURL: URL { url.appendingPathComponent("metadata") }
}

/// Proof that the user explicitly asked to destroy a VM's data. Must be built by the
/// caller for a specific VM id; there is no default.
public struct DeletionConfirmation: Sendable {
    let vmID: UUID
    public init(confirmingDeletionOf vmID: UUID) { self.vmID = vmID }
}

public enum ConfigurationMigrator {
    /// Decodes config.json of any supported schema version into the current model.
    public static func decode(_ data: Data) throws -> VMConfiguration {
        struct Probe: Decodable { var schemaVersion: Int }
        let probe: Probe
        do { probe = try NexVMJSON.decoder().decode(Probe.self, from: data) } catch {
            throw StorageError.corrupted("config.json: \(error.localizedDescription)")
        }
        let current = VMConfiguration.currentSchemaVersion
        guard probe.schemaVersion >= 1 else { throw StorageError.corrupted("invalid schemaVersion") }
        guard probe.schemaVersion <= current else {
            throw StorageError.unsupportedSchema(found: probe.schemaVersion, supported: current)
        }
        // v1 is the only version so far; future versions add upgrade steps here.
        do { return try NexVMJSON.decoder().decode(VMConfiguration.self, from: data) } catch {
            throw StorageError.corrupted("config.json: \(error.localizedDescription)")
        }
    }
}

public struct LibraryListing: Sendable {
    public var bundles: [VMBundle]
    public var failures: [(url: URL, error: StorageError)]
}

/// A directory of `<uuid>.nexvm` bundles. Bundle directory names are derived from the
/// VM UUID, never from user input, so VM names cannot cause path traversal.
public struct VMLibrary: Sendable {
    public static let bundleExtension = "nexvm"
    public let root: URL

    public init(root: URL) { self.root = root }

    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/NexVM/Machines", isDirectory: true)
    }

    private var removedRoot: URL { root.appendingPathComponent(".removed", isDirectory: true) }

    public func bundle(for id: UUID) -> VMBundle {
        VMBundle(url: root.appendingPathComponent("\(id.uuidString).\(Self.bundleExtension)", isDirectory: true))
    }

    /// Creates the bundle in a staging directory and renames it into place atomically.
    public func create(_ configuration: VMConfiguration) throws -> VMBundle {
        let fm = FileManager.default
        let final = bundle(for: configuration.id)
        guard !fm.fileExists(atPath: final.url.path) else { throw StorageError.alreadyExists(final.url.lastPathComponent) }
        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let staging = VMBundle(url: root.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true))
            try fm.createDirectory(at: staging.url, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            do {
                for dir in [staging.disksURL, staging.logsURL, staging.metadataURL] {
                    try fm.createDirectory(at: dir, withIntermediateDirectories: false)
                }
                let manifest = BundleManifest(formatVersion: BundleManifest.currentFormatVersion,
                                              vmID: configuration.id, createdAt: configuration.createdAt)
                try NexVMJSON.encoder().encode(manifest).write(to: staging.manifestURL, options: .atomic)
                try NexVMJSON.encoder().encode(configuration).write(to: staging.configURL, options: .atomic)
                try fm.moveItem(at: staging.url, to: final.url)
            } catch {
                try? fm.removeItem(at: staging.url)  // our own staging dir only
                throw error
            }
        } catch let e as StorageError {
            throw e
        } catch {
            throw StorageError.io(error.localizedDescription)
        }
        return final
    }

    public func load(_ bundle: VMBundle) throws -> VMConfiguration {
        guard FileManager.default.fileExists(atPath: bundle.configURL.path) else {
            throw StorageError.notFound(bundle.configURL.lastPathComponent)
        }
        let data: Data
        do { data = try Data(contentsOf: bundle.configURL) } catch { throw StorageError.io(error.localizedDescription) }
        let config = try ConfigurationMigrator.decode(data)
        guard bundle.url.lastPathComponent == "\(config.id.uuidString).\(Self.bundleExtension)" else {
            throw StorageError.corrupted("bundle name does not match VM id")
        }
        return config
    }

    /// Atomic replace; a crash mid-write leaves the previous config.json intact.
    public func save(_ configuration: VMConfiguration, in bundle: VMBundle) throws {
        var updated = configuration
        updated.updatedAt = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))
        do { try NexVMJSON.encoder().encode(updated).write(to: bundle.configURL, options: .atomic) } catch {
            throw StorageError.io(error.localizedDescription)
        }
    }

    public func list() throws -> LibraryListing {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return LibraryListing(bundles: [], failures: []) }
        let items = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        var bundles: [VMBundle] = []
        var failures: [(URL, StorageError)] = []
        for url in items where url.pathExtension == Self.bundleExtension {
            let b = VMBundle(url: url)
            do { _ = try load(b); bundles.append(b) } catch let e as StorageError { failures.append((url, e)) }
        }
        bundles.sort { $0.url.lastPathComponent < $1.url.lastPathComponent }
        return LibraryListing(bundles: bundles, failures: failures)
    }

    /// Hides the VM from the library but keeps every byte (moved to `.removed/`).
    @discardableResult
    public func removeFromLibrary(_ bundle: VMBundle) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: removedRoot, withIntermediateDirectories: true)
        let dest = removedRoot.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(bundle.url.lastPathComponent)")
        do { try fm.moveItem(at: bundle.url, to: dest) } catch { throw StorageError.io(error.localizedDescription) }
        return dest
    }

    /// Permanently deletes the VM bundle, including disks. Requires explicit confirmation
    /// for this exact VM and refuses locked (running) VMs and paths outside the library.
    public func deleteData(of bundle: VMBundle, confirmation: DeletionConfirmation?) throws {
        guard let confirmation else { throw StorageError.deletionNotConfirmed }
        let config = try load(bundle)
        guard config.id == confirmation.vmID else { throw StorageError.deletionNotConfirmed }
        _ = try PathValidator.resolve(bundle.url.lastPathComponent, under: root)
        let lock = try VMLock(bundleURL: bundle.url)  // throws .locked if running
        defer { lock.release() }
        do { try FileManager.default.removeItem(at: bundle.url) } catch { throw StorageError.io(error.localizedDescription) }
    }
}
