import XCTest
import NexVMCore
@testable import NexVMStorage

final class StorageTests: XCTestCase {
    var tmp: URL!
    var library: VMLibrary!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nexvm-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        library = VMLibrary(root: tmp.appendingPathComponent("lib"))
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    func makeConfig(name: String = "Test VM") -> VMConfiguration {
        VMConfiguration(name: name, guest: .linuxARM64, cpuCount: 2, memoryMiB: 2048,
                        disks: [DiskConfiguration(relativePath: "disks/main.img", sizeGiB: 8, format: .raw, interface: .virtioBlk)])
    }

    func testCreateWritesBundleLayoutAndLoads() throws {
        let c = makeConfig()
        let b = try library.create(c)
        let fm = FileManager.default
        for p in ["manifest.json", "config.json", "disks", "logs", "metadata"] {
            XCTAssertTrue(fm.fileExists(atPath: b.url.appendingPathComponent(p).path), p)
        }
        XCTAssertEqual(try library.load(b), c)
        XCTAssertEqual(b.url.lastPathComponent, "\(c.id.uuidString).nexvm")
    }

    func testCreateTwiceFailsAndLeavesNoStaging() throws {
        let c = makeConfig()
        _ = try library.create(c)
        XCTAssertThrowsError(try library.create(c))
        let names = try FileManager.default.contentsOfDirectory(atPath: library.root.path)
        XCTAssertFalse(names.contains { $0.hasPrefix(".staging-") })
    }

    func testMaliciousNameDoesNotAffectPath() throws {
        let b = try library.create(makeConfig(name: "../../evil"))
        XCTAssertEqual(b.url.deletingLastPathComponent().standardizedFileURL.path, library.root.standardizedFileURL.path)
    }

    func testListReportsCorruptedBundleWithoutFailingOthers() throws {
        let good = try library.create(makeConfig())
        let bad = try library.create(makeConfig(name: "bad"))
        try Data("{ not json".utf8).write(to: bad.configURL)
        let listing = try library.list()
        XCTAssertEqual(listing.bundles.map(\.url.lastPathComponent), [good.url.lastPathComponent])
        XCTAssertEqual(listing.failures.count, 1)
    }

    func testFutureSchemaIsRejected() throws {
        let b = try library.create(makeConfig())
        var json = try String(contentsOf: b.configURL, encoding: .utf8)
        json = json.replacingOccurrences(of: "\"schemaVersion\" : 1", with: "\"schemaVersion\" : 99")
        try json.write(to: b.configURL, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try library.load(b)) {
            XCTAssertEqual($0 as? StorageError, .unsupportedSchema(found: 99, supported: 1))
        }
    }

    func testSaveUpdatesTimestampAtomically() throws {
        var c = makeConfig()
        let b = try library.create(c)
        c.name = "Renamed"
        try library.save(c, in: b)
        let loaded = try library.load(b)
        XCTAssertEqual(loaded.name, "Renamed")
        XCTAssertGreaterThanOrEqual(loaded.updatedAt, c.createdAt)
    }

    func testRemoveFromLibraryKeepsData() throws {
        let b = try library.create(makeConfig())
        let moved = try library.removeFromLibrary(b)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.appendingPathComponent("config.json").path))
        XCTAssertEqual(try library.list().bundles, [])
    }

    func testDeleteRequiresMatchingConfirmation() throws {
        let c = makeConfig()
        let b = try library.create(c)
        XCTAssertThrowsError(try library.deleteData(of: b, confirmation: nil))
        XCTAssertThrowsError(try library.deleteData(of: b, confirmation: DeletionConfirmation(confirmingDeletionOf: UUID())))
        XCTAssertTrue(FileManager.default.fileExists(atPath: b.url.path))
        try library.deleteData(of: b, confirmation: DeletionConfirmation(confirmingDeletionOf: c.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b.url.path))
    }

    func testLockedVMCannotBeDeletedOrLockedTwice() throws {
        let c = makeConfig()
        let b = try library.create(c)
        let lock = try VMLock(bundleURL: b.url)
        XCTAssertThrowsError(try VMLock(bundleURL: b.url)) { XCTAssertTrue(($0 as? StorageError).map { if case .locked = $0 { true } else { false } } ?? false) }
        XCTAssertThrowsError(try library.deleteData(of: b, confirmation: DeletionConfirmation(confirmingDeletionOf: c.id)))
        lock.release()
        XCTAssertNoThrow(try VMLock(bundleURL: b.url))
    }

    func testPathValidator() throws {
        let base = tmp!
        XCTAssertNoThrow(try PathValidator.resolve("disks/a.img", under: base))
        for bad in ["", "/etc/passwd", "../x", "a/../../x", "a\0b"] {
            XCTAssertThrowsError(try PathValidator.resolve(bad, under: base), bad)
        }
        let outside = tmp.appendingPathComponent("outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let inside = tmp.appendingPathComponent("inside")
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: inside.appendingPathComponent("link"), withDestinationURL: outside)
        XCTAssertThrowsError(try PathValidator.resolve("link/file", under: inside)) {
            XCTAssertEqual($0 as? StorageError, .pathEscapesBase("link/file"))
        }
    }

    func testSparseDiskCreation() throws {
        let b = try library.create(makeConfig())
        let url = try DiskImageCreator.createSparseRaw(in: b, relativePath: "disks/main.img", sizeGiB: 1)
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64
        XCTAssertEqual(size, 1024 * 1024 * 1024)
        XCTAssertThrowsError(try DiskImageCreator.createSparseRaw(in: b, relativePath: "disks/main.img", sizeGiB: 1))
        XCTAssertThrowsError(try DiskImageCreator.createSparseRaw(in: b, relativePath: "../escape.img", sizeGiB: 1))
    }

    func testISOValidator() throws {
        let iso = tmp.appendingPathComponent("ok.iso")
        var bytes = Data(count: 0x8000)
        bytes.append(contentsOf: [0x01] + Array("CD001".utf8))
        try bytes.write(to: iso)
        XCTAssertNoThrow(try ISOValidator.validate(path: iso.path))

        let bad = tmp.appendingPathComponent("bad.iso")
        try Data(count: 0x9000).write(to: bad)
        XCTAssertThrowsError(try ISOValidator.validate(path: bad.path)) { XCTAssertEqual($0 as? ISOValidator.Issue, .missingISO9660Signature) }
        XCTAssertThrowsError(try ISOValidator.validate(path: tmp.appendingPathComponent("nope.iso").path))
        let txt = tmp.appendingPathComponent("a.txt"); try bytes.write(to: txt)
        XCTAssertThrowsError(try ISOValidator.validate(path: txt.path)) { XCTAssertEqual($0 as? ISOValidator.Issue, .wrongExtension) }
    }
}
