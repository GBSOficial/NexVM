import XCTest
import CoreGraphics
import Darwin
@testable import NexVMDisplay

/// Plays the server side of an RFB 3.8 session over a socketpair.
final class MockServer: @unchecked Sendable {
    let fd: Int32
    init(fd: Int32) { self.fd = fd }

    func write(_ b: [UInt8]) {
        var sent = 0
        while sent < b.count {
            let n = b.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + sent, b.count - sent) }
            if n <= 0 { return }
            sent += n
        }
    }
    func read(_ n: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: n); var got = 0
        while got < n {
            let r = out.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress! + got, n - got) }
            if r <= 0 { break }
            got += r
        }
        return Array(out[0..<got])
    }
    func closeSocket() { Darwin.close(fd) }

    static func be16(_ v: Int) -> [UInt8] { [UInt8(v >> 8), UInt8(v & 0xFF)] }
    static func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }

    struct HandshakeBytes { var pixelFormat: [UInt8]; var encodings: [UInt8]; var request: [UInt8] }

    func handshake(width: Int, height: Int, name: String = "mock", securityTypes: [UInt8] = [1]) -> HandshakeBytes? {
        write(Array("RFB 003.008\n".utf8))
        _ = read(12)
        write([UInt8(securityTypes.count)] + securityTypes)
        guard securityTypes.contains(1) else { return nil }
        _ = read(1)
        write(Self.be32(0))
        _ = read(1)
        write(Self.be16(width) + Self.be16(height) + [UInt8](repeating: 0, count: 16) + Self.be32(UInt32(name.utf8.count)) + Array(name.utf8))
        let pf = read(20)
        let enc = read(4 + 4 * 4)
        let req = read(10)
        return HandshakeBytes(pixelFormat: pf, encodings: enc, request: req)
    }

    func update(rects: [(x: Int, y: Int, w: Int, h: Int, enc: Int32, body: [UInt8])]) {
        var m: [UInt8] = [0, 0] + Self.be16(rects.count)
        for r in rects { m += Self.be16(r.x) + Self.be16(r.y) + Self.be16(r.w) + Self.be16(r.h) + Self.be32(UInt32(bitPattern: r.enc)) + r.body }
        write(m)
    }
}

final class Frames: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [RFBFrame] = []
    private(set) var closeError: RFBError??
    func add(_ f: RFBFrame) { lock.withLock { all.append(f) } }
    func setClose(_ e: RFBError?) { lock.withLock { closeError = .some(e) } }
    var last: RFBFrame? { lock.withLock { all.last } }
    var count: Int { lock.withLock { all.count } }
    var closed: Bool { lock.withLock { closeError != nil } }
    var closeValue: RFBError? { lock.withLock { closeError ?? nil } }
}

func bytes(of frame: RFBFrame) -> [UInt8] {
    let data = frame.image.dataProvider!.data! as Data
    return [UInt8](data)
}

func waitFor(_ cond: @escaping () -> Bool, timeout: TimeInterval = 5) async throws {
    let end = Date().addingTimeInterval(timeout)
    while !cond() {
        if Date() > end { XCTFail("timeout"); return }
        try await Task.sleep(for: .milliseconds(10))
    }
}

final class RFBClientTests: XCTestCase {
    private func makePair() -> (RFBClient, MockServer, Frames) {
        var fds: [Int32] = [0, 0]
        XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, &fds), 0)
        let frames = Frames()
        let client = RFBClient(fd: fds[0], onFrame: { frames.add($0) }, onClose: { frames.setClose($0) })
        return (client, MockServer(fd: fds[1]), frames)
    }

    /// Runs a full handshake and returns the bytes the client sent.
    private func connect(_ client: RFBClient, _ server: MockServer, width: Int, height: Int) async throws -> MockServer.HandshakeBytes {
        let box = ResultBox()
        let t = Thread { box.set(server.handshake(width: width, height: height)) }
        t.start()
        try await client.performHandshake()
        try await waitFor { box.value != nil }
        client.startReadLoop()
        return box.value!
    }

    final class ResultBox: @unchecked Sendable {
        private let lock = NSLock(); private var v: MockServer.HandshakeBytes?
        func set(_ x: MockServer.HandshakeBytes?) { lock.withLock { v = x } }
        var value: MockServer.HandshakeBytes? { lock.withLock { v } }
    }

    func testHandshakeSendsPixelFormatEncodingsAndFullRequest() async throws {
        let (c, s, _) = makePair()
        let hb = try await connect(c, s, width: 4, height: 3)
        XCTAssertEqual(c.framebufferSize.width, 4); XCTAssertEqual(c.framebufferSize.height, 3)
        XCTAssertEqual(c.desktopName, "mock")
        XCTAssertEqual(hb.pixelFormat, RFBClient.setPixelFormat())
        XCTAssertEqual(Array(hb.pixelFormat[4...7]), [32, 24, 0, 1])           // 32bpp, depth 24, little endian, true colour
        XCTAssertEqual(hb.encodings, RFBClient.setEncodings([-258, -223, 1, 0]))
        XCTAssertEqual(hb.request, [3, 0, 0, 0, 0, 0, 0, 4, 0, 3])             // non-incremental, whole 4x3
        c.close(); s.closeSocket()
    }

    func testRawRectPaintsPixelsAndRequestsIncrementalUpdate() async throws {
        let (c, s, frames) = makePair()
        _ = try await connect(c, s, width: 2, height: 2)
        s.update(rects: [(0, 0, 2, 1, 0, [1, 2, 3, 0, 4, 5, 6, 0])])
        try await waitFor { frames.count > 0 }
        let px = bytes(of: frames.last!)
        XCTAssertEqual(Array(px[0..<8]), [1, 2, 3, 0, 4, 5, 6, 0])
        XCTAssertEqual(Array(px[8..<16]), [UInt8](repeating: 0, count: 8))
        XCTAssertEqual(s.read(10), [3, 1, 0, 0, 0, 0, 0, 2, 0, 2])             // next request is incremental
        c.close(); s.closeSocket()
    }

    func testCopyRectAndDesktopSizeAndExtendedKeyAck() async throws {
        let (c, s, frames) = makePair()
        _ = try await connect(c, s, width: 2, height: 2)
        s.update(rects: [(0, 0, 1, 1, 0, [9, 8, 7, 0]), (1, 1, 1, 1, 1, [0, 0, 0, 0]), (0, 0, 0, 0, -258, [])])
        try await waitFor { frames.count > 0 && c.extendedKeysAcknowledged }
        let px = bytes(of: frames.last!)
        XCTAssertEqual(Array(px[12..<16]), [9, 8, 7, 0])                        // (1,1) now holds the copied pixel
        _ = s.read(10)
        s.update(rects: [(0, 0, 3, 1, -223, [])])
        try await waitFor { c.framebufferSize.width == 3 }
        XCTAssertEqual(c.framebufferSize.height, 1)
        c.close(); s.closeSocket()
    }

    func testInputMessagesAreEncodedAndPointerIsClamped() async throws {
        let (c, s, _) = makePair()
        _ = try await connect(c, s, width: 2, height: 2)
        XCTAssertTrue(c.sendKey(macKeyCode: 0x00, down: true))                  // kVK_ANSI_A → XT 0x1E
        XCTAssertEqual(s.read(12), [255, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0x1E])
        XCTAssertTrue(c.sendKey(macKeyCode: 0x7E, down: false))                 // Up arrow → E0 48
        XCTAssertEqual(s.read(12), [255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xC8])
        XCTAssertFalse(c.sendKey(macKeyCode: 0x3F, down: true))                 // Fn has no PC scancode
        XCTAssertTrue(c.sendPointer(x: 100, y: -5, buttons: 1))
        XCTAssertEqual(s.read(6), [5, 1, 0, 1, 0, 0])                           // clamped to (1, 0)
        c.close(); s.closeSocket()
    }

    func testServerCloseIsReported() async throws {
        let (c, s, frames) = makePair()
        _ = try await connect(c, s, width: 2, height: 2)
        s.closeSocket()
        try await waitFor { frames.closed }
        XCTAssertEqual(frames.closeValue, .closed)
    }

    func testRectOutsideFramebufferIsRejected() async throws {
        let (c, s, frames) = makePair()
        _ = try await connect(c, s, width: 2, height: 2)
        s.update(rects: [(1, 1, 2, 2, 0, [UInt8](repeating: 0, count: 16))])
        try await waitFor { frames.closed }
        XCTAssertEqual(frames.closeValue, .protocolError("rect outside framebuffer"))
        s.closeSocket()
    }

    func testOnlyUnsupportedSecurityFails() async throws {
        let (c, s, _) = makePair()
        let t = Thread { _ = s.handshake(width: 1, height: 1, securityTypes: [2]) }
        t.start()
        do { try await c.performHandshake(); XCTFail("must fail") } catch { XCTAssertEqual(error as? RFBError, .unsupportedSecurity) }
        c.close(); s.closeSocket()
    }

    func testMacKeyMapSpotChecks() {
        XCTAssertEqual(MacKeyMap.xtCode(forMacKeyCode: 0x24), 0x1C)             // Return
        XCTAssertEqual(MacKeyMap.xtCode(forMacKeyCode: 0x33), 0x0E)             // Backspace
        XCTAssertEqual(MacKeyMap.xtCode(forMacKeyCode: 0x75), MacKeyMap.delete) // Forward delete → E0 53
        XCTAssertEqual(MacKeyMap.xtCode(forMacKeyCode: 0x37), 0x5B | 0x80)      // Command → left Windows
        XCTAssertNil(MacKeyMap.xtCode(forMacKeyCode: 0x3F))
        // Every mapped scancode is unique except none; guards against copy-paste mistakes in the table.
        let codes = (UInt16(0)...0x7F).compactMap { MacKeyMap.xtCode(forMacKeyCode: $0) }
        XCTAssertEqual(Set(codes).count, codes.count)
    }
}
