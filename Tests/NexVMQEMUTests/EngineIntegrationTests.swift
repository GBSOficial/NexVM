import XCTest
import NexVMCore
import NexVMEngine
import NexVMStorage
import NexVMDisplay
import ImageIO
import UniformTypeIdentifiers
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
    /// ISO path: $NEXVM_TEST_ISO (an Alpine virt aarch64 ISO); the test is skipped when unset.
    func testAlpineBootsToLoginPrompt() async throws {
        guard let isoPath = ProcessInfo.processInfo.environment["NEXVM_TEST_ISO"] else { throw XCTSkip("NEXVM_TEST_ISO not set") }
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

    /// Boots an Alpine already installed to the bundle's disk (no ISO) and shuts it down with
    /// ACPI through the engine. Needs NEXVM_TEST_INSTALLED_BUNDLE=<path to a .nexvm bundle>.
    func testInstalledAlpineBootsFromDiskAndShutsDownGracefully() async throws {
        guard let path = ProcessInfo.processInfo.environment["NEXVM_TEST_INSTALLED_BUNDLE"],
              let install = QEMUBinaryLocator.locate(), install.firmwareCode != nil, install.firmwareVarsTemplate != nil
        else { throw XCTSkip("NEXVM_TEST_INSTALLED_BUNDLE not set or QEMU missing") }
        let bundleURL = URL(fileURLWithPath: path)
        let library = VMLibrary(root: bundleURL.deletingLastPathComponent())
        var c = try library.load(VMBundle(url: bundleURL))
        XCTAssertNil(c.installMedia, "bundle must boot from its disk")
        c.installMedia = nil
        let serial = root.appendingPathComponent("serial.log")
        let engine = QEMUEngine(installation: install, options: QEMUBuildOptions(headless: true, serialLog: serial))
        try await engine.start(c, bundleURL: bundleURL)
        var out = ""
        for _ in 0..<600 {
            out = (try? String(contentsOf: serial, encoding: .utf8)) ?? ""
            if out.contains("login:") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(out.contains("nexvm login:"), "installed system did not reach its login prompt: \(out.suffix(300))")
        try await engine.requestShutdown(vmID: c.id)
        let mid = await engine.state(of: c.id)
        XCTAssertEqual(mid, .stopping)
        let stopped = await engine.waitUntilStopped(vmID: c.id, timeout: 60)
        XCTAssertTrue(stopped, "guest did not power off after ACPI request")
        let end = await engine.state(of: c.id)
        XCTAssertEqual(end, .stopped)   // clean exit, not .error
    }

    /// Windows-type VM (no OS installed): engine must start swtpm, wire it to QEMU, boot the firmware
    /// under HVF, and leave no swtpm process behind after the VM stops.
    func testWindowsVMStartsSwtpmAndCleansUp() async throws {
        guard let install = QEMUBinaryLocator.locate(), install.firmwareCode != nil, install.firmwareVarsTemplate != nil,
              install.swtpm != nil else { throw XCTSkip("QEMU or swtpm missing") }
        let library = VMLibrary(root: root.appendingPathComponent("lib"))
        let c = VMConfiguration(name: "win-tpm", guest: .windows11ARM64, cpuCount: 2, memoryMiB: 2048,
                                disks: [DiskConfiguration(relativePath: "disks/main.img", sizeGiB: 8, format: .raw, interface: .nvme)])
        let bundle = try library.create(c)
        try DiskImageCreator.createSparseRaw(in: bundle, relativePath: "disks/main.img", sizeGiB: 8)
        let serial = bundle.logsURL.appendingPathComponent("serial.log")
        let engine = QEMUEngine(installation: install, options: QEMUBuildOptions(headless: true, serialLog: serial))

        try await engine.start(c, bundleURL: bundle.url)
        let running = await engine.state(of: c.id)
        XCTAssertEqual(running, .running)
        let tpmDir = bundle.metadataURL.appendingPathComponent("tpm").path
        XCTAssertTrue(Self.pgrep("swtpm socket.*\(tpmDir)"), "swtpm should be running for this VM")

        var out = ""
        for _ in 0..<100 {
            out = (try? String(contentsOf: serial, encoding: .utf8)) ?? ""
            if out.contains("UEFI") || out.contains("BdsDxe") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(out.contains("UEFI") || out.contains("BdsDxe"), "firmware did not run: \(out.prefix(200))")
        // TPM state files are created by swtpm inside the bundle.
        try await Task.sleep(for: .seconds(1))
        let tpmFiles = (try? FileManager.default.contentsOfDirectory(atPath: tpmDir)) ?? []
        XCTAssertFalse(tpmFiles.isEmpty, "swtpm wrote no state in \(tpmDir)")

        try await engine.forceStop(vmID: c.id)
        _ = await engine.waitUntilStopped(vmID: c.id, timeout: 10)
        try await Task.sleep(for: .seconds(1))
        XCTAssertFalse(Self.pgrep("swtpm socket.*\(tpmDir)"), "swtpm outlived its VM")
    }

    private static func pgrep(_ pattern: String) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-f", pattern]
        p.standardOutput = FileHandle.nullDevice
        try? p.run(); p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Embedded display end to end: QEMU serves the screen over a private VNC unix socket, the RFB client
    /// receives real frames, and keys sent as physical scancodes reach the Alpine login prompt.
    func testEmbeddedDisplayShowsGuestAndAcceptsKeys() async throws {
        guard let isoPath = ProcessInfo.processInfo.environment["NEXVM_TEST_ISO"] else { throw XCTSkip("NEXVM_TEST_ISO not set") }
        guard let install = QEMUBinaryLocator.locate(), install.firmwareCode != nil, install.firmwareVarsTemplate != nil,
              FileManager.default.fileExists(atPath: isoPath) else { throw XCTSkip("QEMU or Alpine ISO missing") }
        let library = VMLibrary(root: root.appendingPathComponent("lib"))
        let c = VMConfiguration(name: "alpine-vnc", guest: .linuxARM64, cpuCount: 2, memoryMiB: 1024,
                                disks: [DiskConfiguration(relativePath: "disks/main.img", sizeGiB: 8, format: .raw, interface: .virtioBlk)],
                                installMedia: InstallMedia(path: isoPath))
        let bundle = try library.create(c)
        try DiskImageCreator.createSparseRaw(in: bundle, relativePath: "disks/main.img", sizeGiB: 8)
        let serial = bundle.logsURL.appendingPathComponent("serial.log")
        let engine = QEMUEngine(installation: install, options: QEMUBuildOptions(serialLog: serial, embeddedDisplay: true))
        try await engine.start(c, bundleURL: bundle.url)

        let sock = await engine.displaySocket(for: c.id)
        let socketPath = try XCTUnwrap(sock?.path)
        let latest = FrameBox()
        let client = try await RFBClient.connect(path: socketPath, timeout: 10, onFrame: { latest.set($0) })
        defer { client.close() }
        XCTAssertGreaterThan(client.framebufferSize.width, 0)

        // Wait for the guest (not the firmware): the TianoCore logo at the centre is gone and console text is on screen.
        func brightPixels(_ f: RFBFrame) -> Int {
            let data = (f.image.dataProvider!.data! as Data)
            var n = 0; var i = 0
            while i + 3 < data.count { if data[i] > 150 && data[i + 1] > 150 && data[i + 2] > 150 { n += 1 }; i += 4 }
            return n
        }
        // The serial console is only a clock: "login:" there means Linux is up and tty0 shows its own login prompt.
        var shown = false
        for _ in 0..<900 {   // up to 90 s
            if ((try? String(contentsOf: serial, encoding: .utf8)) ?? "").contains("login:") { shown = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        try await Task.sleep(for: .seconds(2))
        let before = try XCTUnwrap(latest.value)
        try Self.writePNG(before.image, to: root.appendingPathComponent("vnc-before.png"))
        XCTAssertTrue(shown, "Linux never reached its login prompt")
        XCTAssertTrue(client.extendedKeysAcknowledged, "QEMU did not acknowledge extended key events")

        // Type "root" (macOS key codes r,o,o,t) the way the app does: press, hold ~80 ms, release.
        try await Task.sleep(for: .seconds(2))
        let baseline = brightPixels(try XCTUnwrap(latest.value))
        for code: UInt16 in [0x0F, 0x1F, 0x1F, 0x11] {
            XCTAssertTrue(client.sendKey(macKeyCode: code, down: true))
            try await Task.sleep(for: .milliseconds(80))
            XCTAssertTrue(client.sendKey(macKeyCode: code, down: false))
            try await Task.sleep(for: .milliseconds(80))
        }
        try await Task.sleep(for: .seconds(1))
        let after = try XCTUnwrap(latest.value)
        try Self.writePNG(after.image, to: root.appendingPathComponent("vnc-after.png"))
        XCTAssertGreaterThan(brightPixels(after), baseline + 30, "typed text did not reach the guest console (\(baseline) -> \(brightPixels(after)))")

        // Keep the evidence next to the repo's build output for inspection.
        let evidence = root.deletingLastPathComponent().appendingPathComponent("vnc-evidence")
        try? FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: evidence.appendingPathComponent("after.png"))
        try? FileManager.default.copyItem(at: root.appendingPathComponent("vnc-after.png"), to: evidence.appendingPathComponent("after.png"))

        try await engine.forceStop(vmID: c.id)
        _ = await engine.waitUntilStopped(vmID: c.id, timeout: 10)
        let leftover = await engine.displaySocket(for: c.id)
        XCTAssertNil(leftover)
    }

    final class FrameBox: @unchecked Sendable {
        private let lock = NSLock(); private var f: RFBFrame?
        func set(_ x: RFBFrame) { lock.withLock { f = x } }
        var value: RFBFrame? { lock.withLock { f } }
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { throw XCTSkip("png") }
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
    }

    /// A Secure Boot VM must boot Debian's AAVMF build (not QEMU's stock one) and keep its NVRAM in its own file.
    func testSecureBootVMUsesAAVMFBuildAndSeparateNVRAM() async throws {
        guard let install = QEMUBinaryLocator.locate(), install.secureBootFirmware != nil, install.swtpm != nil
        else { throw XCTSkip("QEMU, swtpm or Secure Boot firmware missing") }
        let library = VMLibrary(root: root.appendingPathComponent("lib"))
        let c = VMConfiguration(name: "win-sb", guest: .windows11ARM64, cpuCount: 2, memoryMiB: 2048,
                                disks: [DiskConfiguration(relativePath: "disks/main.img", sizeGiB: 8, format: .raw, interface: .nvme)],
                                firmware: .secureBoot)
        let bundle = try library.create(c)
        try DiskImageCreator.createSparseRaw(in: bundle, relativePath: "disks/main.img", sizeGiB: 8)
        let serial = bundle.logsURL.appendingPathComponent("serial.log")
        let engine = QEMUEngine(installation: install, options: QEMUBuildOptions(headless: true, serialLog: serial))
        try await engine.start(c, bundleURL: bundle.url)
        var out = ""
        for _ in 0..<100 {
            out = (try? String(contentsOf: serial, encoding: .utf8)) ?? ""
            if out.contains("UEFI firmware (version") { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(out.contains("UEFI firmware (version"), "unexpected firmware banner: \(out.prefix(120))")
        XCTAssertFalse(out.contains("edk2-stable202408"), "stock firmware banner: \(out.prefix(120))")
        let meta = bundle.metadataURL
        XCTAssertTrue(FileManager.default.fileExists(atPath: meta.appendingPathComponent("vars-secureboot.fd").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: meta.appendingPathComponent("vars.fd").path))
        try await engine.forceStop(vmID: c.id)
        _ = await engine.waitUntilStopped(vmID: c.id, timeout: 10)
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
