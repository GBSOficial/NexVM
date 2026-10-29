import XCTest
@testable import NexVMDiagnostics

final class LoggerTests: XCTestCase {
    func testWritesJSONLinesFiltersLevelAndRestrictsPermissions() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nexvm-log-\(UUID())/app.log")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let logger = StructuredLogger(fileURL: url, minimumLevel: .info)
        let id = UUID()
        await logger.log(.debug, "t", "hidden")
        await logger.log(.info, "engine", "started", vmID: id)
        await logger.log(.error, "engine", "boom")
        await logger.close()

        let entries = try LogReader.read(fileURL: url)
        XCTAssertEqual(entries.map(\.message), ["started", "boom"])
        XCTAssertEqual(entries.first?.vmID, id)
        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }
}
