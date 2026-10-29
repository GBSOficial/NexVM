import XCTest
@testable import NexVMCore

final class ConfigurationTests: XCTestCase {
    let m4 = HostResources(physicalMemoryMiB: 16384, cpuCores: 10, isAppleSilicon: true, availableDiskGiB: 400)

    func config(mem: Int = 4096, cpu: Int = 4, disk: Int = 64, name: String = "Win") -> VMConfiguration {
        VMConfiguration(name: name, guest: .windows11ARM64, cpuCount: cpu, memoryMiB: mem,
                        disks: [DiskConfiguration(relativePath: "disks/main.img", sizeGiB: disk, format: .raw, interface: .nvme)])
    }

    func testValidConfigurationHasNoIssues() {
        XCTAssertEqual(ConfigurationValidator.validate(config(), host: m4), [])
    }

    func testMemoryLimitIsHalfOfHost() {
        XCTAssertEqual(ResourcePolicy.maxMemoryMiB(host: m4), 8192)
        XCTAssertEqual(ConfigurationValidator.validate(config(mem: 9000), host: m4), [.memoryExceedsLimit(maxMiB: 8192)])
        XCTAssertEqual(ConfigurationValidator.validate(config(mem: 512), host: m4), [.memoryTooLow(minMiB: 1024)])
    }

    func testCPULimitLeavesTwoCoresToHost() {
        XCTAssertEqual(ResourcePolicy.maxCPUCount(host: m4), 8)
        XCTAssertEqual(ConfigurationValidator.validate(config(cpu: 9), host: m4), [.cpuOutOfRange(max: 8)])
        XCTAssertEqual(ConfigurationValidator.validate(config(cpu: 0), host: m4), [.cpuOutOfRange(max: 8)])
    }

    func testNameAndDiskIssues() {
        XCTAssertTrue(ConfigurationValidator.validate(config(name: "  "), host: m4).contains(.emptyName))
        XCTAssertTrue(ConfigurationValidator.validate(config(disk: 4), host: m4).contains(.diskTooSmall(minGiB: 8)))
        XCTAssertTrue(ConfigurationValidator.validate(config(disk: 500), host: m4)
            .contains(.insufficientHostDisk(neededGiB: 500, availableGiB: 400)))
    }

    func testRejectsAbsoluteDiskPathAndIntel() {
        var c = config()
        c.disks[0].relativePath = "/etc/passwd"
        XCTAssertTrue(ConfigurationValidator.validate(c, host: m4).contains(.absoluteDiskPath("/etc/passwd")))
        var intel = m4; intel.isAppleSilicon = false
        XCTAssertTrue(ConfigurationValidator.validate(config(), host: intel).contains(.unsupportedHost))
    }

    func testRecommendationsStayWithinLimits() {
        let win = ResourcePolicy.recommendation(for: .windows11ARM64, host: m4)
        XCTAssertEqual(win.memoryMiB, 4096)
        XCTAssertEqual(win.cpuCount, 4)
        let small = HostResources(physicalMemoryMiB: 8192, cpuCores: 4, isAppleSilicon: true, availableDiskGiB: 30)
        let r = ResourcePolicy.recommendation(for: .windows11ARM64, host: small)
        XCTAssertEqual(r.memoryMiB, 4096)
        XCTAssertEqual(r.cpuCount, 2)
        XCTAssertEqual(r.diskGiB, 15)
    }

    func testCodableRoundTripKeepsSchemaVersion() throws {
        let c = config()
        let data = try NexVMJSON.encoder().encode(c)
        let back = try NexVMJSON.decoder().decode(VMConfiguration.self, from: data)
        XCTAssertEqual(back.schemaVersion, VMConfiguration.currentSchemaVersion)
        XCTAssertEqual(back.id, c.id)
        XCTAssertEqual(back.disks, c.disks)
    }

    func testHostProbeReturnsPlausibleValues() {
        let h = HostResources.current()
        XCTAssertGreaterThan(h.physicalMemoryMiB, 0)
        XCTAssertGreaterThan(h.cpuCores, 0)
    }
}
