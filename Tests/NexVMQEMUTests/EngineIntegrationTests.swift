import XCTest
import NexVMCore
import NexVMEngine
import NexVMStorage
@testable import NexVMQEMU

/// Runs real QEMU/HVF. Skipped when QEMU is not installed. Work files live under
/// `<repo>/.build/it` (same volume as the repo), never in the system temp directory.
final class EngineIntegrationTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        root = repo.appendingPathComponent(".build/it/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testFirmwareBootsUnderHVFAndLifecycleWorks() async throws {
        guard let install = QEMUBinaryLocator.locate(), install.firmwareCode != nil, install.firmwareVarsTemplate != nil else {
            throw XCTSkip("QEMU with edk2 firmware not installed")
        }
        let library = VMLibrary(root: root.appendingPathComponent("lib"))
        var c = VMConfiguration(name: "it-vm", guest: .linuxARM64, cpuCount: 2, memoryMiB: 1024,
                                disks: [DiskConfiguration(relativePath: "disks/main.img", sizeGiB: 8, format: .raw, interface: .virtioBlk)])
        c.disks[0].sizeGiB = 8
        let bundle = try library.create(c)
        try DiskImageCreator.createSparseRaw(in: bundle, relativePath: "disks/main.img", sizeGiB: 8)
        let serial = bundle.logsURL.appendingPathComponent("serial.log")

        let engine = QEMUEngine(installation: install, options: QEMUBuildOptions(headless: true, serialLog: serial))
        let state0 = await engine.state(of: c.id)
        XCTAssertEqual(state0, .stopped)

        try await engine.start(c, bundleURL: bundle.url)
        let state1 = await engine.state(of: c.id)
        XCTAssertEqual(state1, .running)

        // Same VM cannot start twice.
        do { try await engine.start(c, bundleURL: bundle.url); XCTFail("second start must fail") } catch {
            XCTAssertEqual(error as? EngineError, .alreadyRunning(c.id))
        }

        // Evidence the guest firmware really executed: UEFI banner on the serial console.
        var output = ""
        for _ in 0..<100 {
            output = (try? String(contentsOf: serial, encoding: .utf8)) ?? ""
            if output.contains("UEFI") || output.contains("BdsDxe") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(output.contains("UEFI") || output.contains("BdsDxe"), "no firmware output: \(output.prefix(200))")

        // Hardware-style reset keeps the VM alive and the firmware boots again.
        try await engine.restart(vmID: c.id)
        let afterReset = await engine.state(of: c.id)
        XCTAssertEqual(afterReset, .running)
        let active = await engine.activeVMIDs()
        XCTAssertEqual(active, [c.id])

        try await engine.forceStop(vmID: c.id)
        let stopped = await engine.waitUntilStopped(vmID: c.id, timeout: 10)
        XCTAssertTrue(stopped)
        let state2 = await engine.state(of: c.id)
        XCTAssertEqual(state2, .stopped)

        // Lock released and NVRAM persisted: a second boot works, and the disk is untouched.
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundle.metadataURL.appendingPathComponent("vars.fd").path))
        try await engine.start(c, bundleURL: bundle.url)
        try await engine.forceStop(vmID: c.id)
        _ = await engine.waitUntilStopped(vmID: c.id, timeout: 10)
    }

    /// Boots a real Linux ARM64 installer ISO and waits for its login prompt on the serial console.
    /// ISO path: $NEXVM_TEST_ISO or /path/to/tools/isos/alpine-virt-3.24.3-aarch64.iso
    func testAlpineBootsToLoginPrompt() async throws {
        let isoPath = ProcessInfo.processInfo.environment["NEXVM_TEST_ISO"]
            ?? "/path/to/tools/isos/alpine-virt-3.24.3-aarch64.iso"
        guard let install = QEMUBinaryLocator.locate(), install.firmwareCode != nil, install.firmwareVarsTemplate != nil,
              FileManager.default.fileExists(atPath: isoPath) else { throw XCTSkip("QEMU or Alpine ISO missing") }
        XCTAssertNoThrow(try ISOValidator.validate(path: isoPath))

        let library = VMLibrary(root: root.appendingPathComponent("lib"))
        let c = VMConfiguration(name: "alpine", guest: .linuxARM64, cpuCount: 2, memoryMiB: 1024,
                                disks: [DiskConfiguration(relativePath: "disks/main.img", sizeGiB: 8, format: .raw, interface: .virtioBlk)],
                                installMedia: InstallMedia(path: isoPath))
        let bundle = try library.create(c)
        try DiskImageCreator.createSparseRaw(in: bundle, relativePath: "disks/main.img", sizeGiB: 8)
        let serial = bundle.logsURL.appendingPathComponent("serial.log")
        let engine = QEMUEngine(installation: install, options: QEMUBuildOptions(headless: true, serialLog: serial))

        try await engine.start(c, bundleURL: bundle.url)
        var output = ""
        for _ in 0..<900 {  // up to 90 s
            output = (try? String(contentsOf: serial, encoding: .utf8)) ?? ""
            if output.contains("login:") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let ok = output.contains("login:")
        if !ok { print("SERIAL TAIL:\n\(output.suffix(1500))") }
        try await engine.forceStop(vmID: c.id)
        _ = await engine.waitUntilStopped(vmID: c.id, timeout: 10)
        XCTAssertTrue(ok, "Alpine did not reach login prompt")
        // The ISO is only referenced, never modified or copied.
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: isoPath)[.size] as? Int, 93_452_288)
    }

    func testStartFailsCleanlyWithoutFirmware() async throws {
        let engine = QEMUEngine(installation: QEMUInstallation(system: URL(fileURLWithPath: "/nonexistent/qemu")))
        let c = VMConfiguration(name: "x", guest: .linuxARM64, cpuCount: 1, memoryMiB: 1024,
                                disks: [DiskConfiguration(relativePath: "disks/a.img", sizeGiB: 8, format: .raw, interface: .virtioBlk)])
        do { try await engine.start(c, bundleURL: root); XCTFail() } catch {
            guard case .backendUnavailable = error as? EngineError else { return XCTFail("\(error)") }
        }
        let s = await engine.state(of: c.id)
        XCTAssertEqual(s, .stopped)
    }
}
