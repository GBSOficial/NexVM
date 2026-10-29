import XCTest
import NexVMCore
import NexVMStorage
@testable import NexVMQEMU

final class QEMUCommandBuilderTests: XCTestCase {
    let install = QEMUInstallation(system: URL(fileURLWithPath: "/opt/homebrew/bin/qemu-system-aarch64"))
    let bundle = VMBundle(url: URL(fileURLWithPath: "/tmp/nexvm-fake/AAAA.nexvm"))
    let fw = QEMUFirmware(code: URL(fileURLWithPath: "/fw/code.fd"), vars: URL(fileURLWithPath: "/tmp/nexvm-fake/AAAA.nexvm/metadata/vars.fd"))
    let qmp = URL(fileURLWithPath: "/tmp/nexvm-fake/qmp.sock")

    func config(guest: GuestOS, name: String = "Win", iface: DiskInterface, iso: String? = nil) -> VMConfiguration {
        VMConfiguration(name: name, guest: guest, cpuCount: 4, memoryMiB: 4096,
                        disks: [DiskConfiguration(relativePath: "disks/main.img", sizeGiB: 64, format: .raw, interface: iface)],
                        installMedia: iso.map(InstallMedia.init(path:)))
    }

    func build(_ c: VMConfiguration, tpm: URL? = nil) throws -> [String] {
        try QEMUCommandBuilder(installation: install).build(configuration: c, bundle: bundle, firmware: fw, qmpSocket: qmp, tpmSocket: tpm).arguments
    }

    func testWindowsUsesHVFNVMeAndE1000e() throws {
        let a = try build(config(guest: .windows11ARM64, iface: .nvme))
        XCTAssertTrue(zip(a, a.dropFirst()).contains { $0 == "-accel" && $1 == "hvf" })
        XCTAssertTrue(a.contains("-cpu") && a.contains("host"))
        XCTAssertTrue(a.contains("4096M"))
        XCTAssertTrue(a.contains { $0.hasPrefix("nvme,drive=disk0") })
        XCTAssertTrue(a.contains("e1000e,netdev=net0"))
        XCTAssertTrue(a.contains("ramfb") && !a.contains("virtio-gpu-pci"))
        XCTAssertFalse(a.contains { $0.contains("hostfwd") })
    }

    func testLinuxUsesVirtio() throws {
        let a = try build(config(guest: .linuxARM64, iface: .virtioBlk))
        XCTAssertTrue(a.contains("virtio-blk-pci,drive=disk0"))
        XCTAssertTrue(a.contains("virtio-net-pci,netdev=net0"))
        XCTAssertTrue(a.contains("virtio-gpu-pci") && !a.contains("ramfb"))
    }

    func testCommasInUserValuesAreEscapedAndNeverSplitArguments() throws {
        let a = try build(config(guest: .linuxARM64, name: "a,b", iface: .virtioBlk, iso: "/Users/x/my,disk.iso"))
        XCTAssertTrue(a.contains("a,,b"))
        XCTAssertTrue(a.contains { $0.hasSuffix("file=/Users/x/my,,disk.iso") })
    }

    func testShellMetacharactersStayInsideSingleArgument() throws {
        let name = "x; rm -rf ~ $(whoami) `id`"
        let a = try build(config(guest: .linuxARM64, name: name, iface: .virtioBlk))
        XCTAssertTrue(a.contains(name))
    }

    func testInstallMediaIsReadOnlyAndBootFirst() throws {
        let a = try build(config(guest: .linuxARM64, iface: .virtioBlk, iso: "/iso/a.iso"))
        XCTAssertTrue(a.contains { $0.contains("media=cdrom,readonly=on") })
        XCTAssertTrue(a.contains("usb-storage,drive=cd0,bootindex=0"))
    }

    func testTPMArgsOnlyWhenSocketProvided() throws {
        let c = config(guest: .windows11ARM64, iface: .nvme)
        XCTAssertFalse(try build(c).contains { $0.contains("tpm") })
        let withTPM = try build(c, tpm: URL(fileURLWithPath: "/tmp/tpm.sock"))
        XCTAssertTrue(withTPM.contains("tpm-tis-device,tpmdev=tpm0"))
    }

    func testQMPIsUnixSocketOnly() throws {
        let a = try build(config(guest: .linuxARM64, iface: .virtioBlk))
        XCTAssertTrue(a.contains("unix:/tmp/nexvm-fake/qmp.sock,server=on,wait=off"))
        XCTAssertFalse(a.contains { $0.hasPrefix("tcp:") })
    }

    func testRejectsTraversalInDiskPathAndEmptyDisks() {
        var c = config(guest: .linuxARM64, iface: .virtioBlk)
        c.disks[0].relativePath = "../../etc/passwd"
        XCTAssertThrowsError(try build(c))
        c.disks = []
        XCTAssertThrowsError(try build(c)) { XCTAssertEqual($0 as? QEMUBuildError, .noDisks) }
    }
}

final class QMPTests: XCTestCase {
    func parse(_ s: String) throws -> QMPMessage { try QMP.parse(Data(s.utf8)) }

    func testGreeting() throws {
        let m = try parse(#"{"QMP": {"version": {"qemu": {"micro": 2, "minor": 1, "major": 11}, "package": ""}, "capabilities": ["oob"]}}"#)
        XCTAssertEqual(m, .greeting(version: "11.1.2"))
    }

    func testSuccessErrorEvent() throws {
        XCTAssertEqual(try parse(#"{"return": {}, "id": "1"}"#), .success(id: "1"))
        XCTAssertEqual(try parse(#"{"error": {"class": "CommandNotFound", "desc": "nope"}, "id": "2"}"#),
                       .failure(errorClass: "CommandNotFound", description: "nope", id: "2"))
        XCTAssertEqual(try parse(#"{"event": "SHUTDOWN", "data": {"guest": true}, "timestamp": {"seconds": 1, "microseconds": 2}}"#),
                       .event(name: "SHUTDOWN"))
    }

    func testMalformedThrows() {
        XCTAssertThrowsError(try parse("garbage"))
        XCTAssertThrowsError(try parse(#"{"foo": 1}"#))
    }

    func testEncode() {
        let d = QMP.encode(.systemPowerdown, id: "7")
        XCTAssertEqual(String(decoding: d, as: UTF8.self), "{\"execute\":\"system_powerdown\",\"id\":\"7\"}\n")
    }
}

final class LocatorTests: XCTestCase {
    func testVersionParsing() {
        XCTAssertEqual(QEMUBinaryLocator.parseVersion("QEMU emulator version 11.1.2\nCopyright (c) 2003-2026"), "11.1.2")
        XCTAssertEqual(QEMUBinaryLocator.parseVersion("QEMU emulator version 9.0.0 (Homebrew)"), "9.0.0")
        XCTAssertNil(QEMUBinaryLocator.parseVersion("hello"))
    }

    func testLocateFindsExecutableAndFirmware() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("nexvm-qemu-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: tmp) }
        let bin = tmp.appendingPathComponent("bin"), share = tmp.appendingPathComponent("share/qemu")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: share, withIntermediateDirectories: true)
        let sys = bin.appendingPathComponent("qemu-system-aarch64")
        try "#!/bin/sh\n".write(to: sys, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sys.path)
        try Data().write(to: share.appendingPathComponent("edk2-aarch64-code.fd"))

        let found = QEMUBinaryLocator.locate(searchDirectories: [bin.path])
        XCTAssertNotNil(found)
        XCTAssertNotNil(found?.firmwareCode)
        XCTAssertNil(found?.imageTool)
        XCTAssertNil(QEMUBinaryLocator.locate(searchDirectories: ["/nonexistent-dir"]))
    }
}

final class ManagedProcessTests: XCTestCase {
    var logURL: URL!
    override func setUp() { logURL = FileManager.default.temporaryDirectory.appendingPathComponent("nexvm-proc-\(UUID()).log") }
    override func tearDown() { try? FileManager.default.removeItem(at: logURL) }

    func testCapturesOutputAndExitCode() async throws {
        let p = ManagedProcess()
        try p.launch(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "echo hello; echo oops >&2; exit 3"], logURL: logURL)
        let code = await p.waitForExit()
        XCTAssertEqual(code, 3)
        let log = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(log.contains("hello") && log.contains("oops"))
    }

    func testTerminateStopsOnlyOwnProcess() async throws {
        let p = ManagedProcess(), bystander = ManagedProcess()
        try p.launch(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["60"], logURL: logURL)
        let other = FileManager.default.temporaryDirectory.appendingPathComponent("nexvm-proc2-\(UUID()).log")
        defer { try? FileManager.default.removeItem(at: other) }
        try bystander.launch(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["60"], logURL: other)
        _ = await p.terminate(grace: 2)
        XCTAssertFalse(p.isRunning)
        XCTAssertTrue(bystander.isRunning)
        _ = await bystander.terminate(grace: 2)
    }

    func testSIGKILLEscalationWhenSIGTERMIgnored() async throws {
        let p = ManagedProcess()
        try p.launch(executable: URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "trap '' TERM; while true; do sleep 1; done"], logURL: logURL)
        try await Task.sleep(for: .milliseconds(300))
        _ = await p.terminate(grace: 1)
        XCTAssertFalse(p.isRunning)
    }

    func testLaunchFailureIsReported() {
        let p = ManagedProcess()
        XCTAssertThrowsError(try p.launch(executable: URL(fileURLWithPath: "/nonexistent/qemu"), arguments: [], logURL: logURL))
    }

    func testWaitTimeoutReturnsNilWhileRunning() async throws {
        let p = ManagedProcess()
        try p.launch(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], logURL: logURL)
        let r = await p.waitForExit(timeout: 0.3)
        XCTAssertNil(r)
        _ = await p.terminate(grace: 2)
    }
}
