import Foundation
import CoreGraphics
import Darwin

public enum RFBError: Error, Equatable, Sendable {
    case connectFailed(String)
    case protocolError(String)
    case unsupportedSecurity
    case serverRefused(String)
    case closed
}

/// A snapshot of the remote framebuffer, ready to draw.
public struct RFBFrame: @unchecked Sendable {
    public let width: Int
    public let height: Int
    public let image: CGImage
}

/// Minimal RFB (VNC) 3.8 client over a unix-domain socket: security "None", Raw + CopyRect +
/// DesktopSize encodings, absolute pointer, and QEMU's extended key event (physical scancodes).
/// Reads run on a dedicated thread; callbacks arrive on arbitrary threads.
public final class RFBClient: @unchecked Sendable {
    // MARK: Limits (defence against a misbehaving server)
    static let maxDimension = 16_384
    static let maxRectBytes = 256 * 1024 * 1024

    private let fd: Int32
    private let lock = NSLock()
    private let writeLock = NSLock()
    private var closed = false

    private var width = 0
    private var height = 0
    private var pixels = [UInt8]()          // BGRA, 4 bytes per pixel, row-major
    private var serverName = ""
    private var extendedKeyAck = false

    private let onFrame: @Sendable (RFBFrame) -> Void
    private let onClose: @Sendable (RFBError?) -> Void
    private let emitQueue = DispatchQueue(label: "nexvm.rfb.emit")
    private var lastEmit = DispatchTime(uptimeNanoseconds: 0)
    private var emitScheduled = false

    // MARK: Connecting

    /// Connects (retrying until `timeout`, since QEMU creates the socket shortly after launch).
    public static func connect(
        path: String, timeout: TimeInterval = 10,
        onFrame: @escaping @Sendable (RFBFrame) -> Void,
        onClose: @escaping @Sendable (RFBError?) -> Void = { _ in }
    ) async throws -> RFBClient {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if let fd = openSocket(path) {
                let client = RFBClient(fd: fd, onFrame: onFrame, onClose: onClose)
                do { try await client.performHandshake(); client.startReadLoop(); return client } catch {
                    client.close(); throw error
                }
            }
            if Date() > deadline { throw RFBError.connectFailed(path) }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    /// For tests and in-process peers: wraps an already connected socket.
    public init(fd: Int32, onFrame: @escaping @Sendable (RFBFrame) -> Void, onClose: @escaping @Sendable (RFBError?) -> Void) {
        self.fd = fd
        self.onFrame = onFrame
        self.onClose = onClose
    }

    private static func openSocket(_ path: String) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { Darwin.close(fd); return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { dst in bytes.withUnsafeBytes { dst.copyMemory(from: $0) } }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        if rc != 0 { Darwin.close(fd); return nil }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    /// Runs the blocking handshake off the cooperative pool.
    public func performHandshake() async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            Thread.detachNewThread {
                do { try self.handshake(); cont.resume() } catch { cont.resume(throwing: error) }
            }
        }
    }

    public func startReadLoop() {
        let t = Thread { [self] in readLoop() }
        t.name = "nexvm.rfb.read"
        t.start()
    }

    public var framebufferSize: (width: Int, height: Int) { lock.withLock { (width, height) } }
    public var desktopName: String { lock.withLock { serverName } }
    public var extendedKeysAcknowledged: Bool { lock.withLock { extendedKeyAck } }

    public func close() {
        let already = lock.withLock { () -> Bool in let a = closed; closed = true; return a }
        if already { return }
        Darwin.shutdown(fd, SHUT_RDWR)
        Darwin.close(fd)
    }

    // MARK: Handshake

    private func handshake() throws {
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        defer { var zero = timeval(tv_sec: 0, tv_usec: 0); setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &zero, socklen_t(MemoryLayout<timeval>.size)) }

        let version = try readBytes(12)
        guard String(decoding: version, as: UTF8.self).hasPrefix("RFB 003.") else { throw RFBError.protocolError("bad version string") }
        try write(Array("RFB 003.008\n".utf8))

        let count = Int(try readBytes(1)[0])
        if count == 0 { throw RFBError.serverRefused(try readReason()) }
        let types = try readBytes(count)
        guard types.contains(1) else { throw RFBError.unsupportedSecurity }   // 1 = None
        try write([1])
        let result = try readU32()
        if result != 0 { throw RFBError.serverRefused(try readReason()) }

        try write([1])                                    // ClientInit: shared
        let w = Int(try readU16()), h = Int(try readU16())
        _ = try readBytes(16)                             // server pixel format (we override it)
        let nameLen = Int(try readU32())
        guard nameLen < 4096 else { throw RFBError.protocolError("name too long") }
        let name = String(decoding: try readBytes(nameLen), as: UTF8.self)
        try resize(width: w, height: h)
        lock.withLock { serverName = name }

        try write(Self.setPixelFormat())
        try write(Self.setEncodings([-258, -223, 1, 0]))   // QEMU ext key, DesktopSize, CopyRect, Raw
        try requestUpdate(incremental: false)
    }

    private func readReason() throws -> String {
        let n = Int(try readU32())
        guard n < 4096 else { throw RFBError.protocolError("reason too long") }
        return String(decoding: try readBytes(n), as: UTF8.self)
    }

    // MARK: Outgoing messages (also used by tests)

    static func setPixelFormat() -> [UInt8] {
        // 32 bpp, depth 24, little-endian, true colour, 8 bits per channel, R<<16 G<<8 B<<0 → memory B,G,R,X
        var m: [UInt8] = [0, 0, 0, 0, 32, 24, 0, 1]
        m += [0, 255, 0, 255, 0, 255, 16, 8, 0, 0, 0, 0]
        return m
    }

    static func setEncodings(_ list: [Int32]) -> [UInt8] {
        var m: [UInt8] = [2, 0, UInt8(list.count >> 8), UInt8(list.count & 0xFF)]
        for e in list { m += be32(UInt32(bitPattern: e)) }
        return m
    }

    static func updateRequest(incremental: Bool, x: Int, y: Int, w: Int, h: Int) -> [UInt8] {
        [3, incremental ? 1 : 0] + be16(x) + be16(y) + be16(w) + be16(h)
    }

    static func keyEvent(down: Bool, keysym: UInt32) -> [UInt8] { [4, down ? 1 : 0, 0, 0] + be32(keysym) }

    /// QEMU extended key event: message 255, submessage 0, down flag, keysym, XT scancode.
    static func extendedKeyEvent(down: Bool, keysym: UInt32, xtCode: UInt32) -> [UInt8] {
        [255, 0] + be16(down ? 1 : 0) + be32(keysym) + be32(xtCode)
    }

    static func pointerEvent(buttons: UInt8, x: Int, y: Int) -> [UInt8] { [5, buttons] + be16(x) + be16(y) }

    private static func be16(_ v: Int) -> [UInt8] { [UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }
    private static func be32(_ v: UInt32) -> [UInt8] { [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)] }

    // MARK: Input API

    /// Sends a physical key press/release using a macOS key code (layout-independent).
    @discardableResult
    public func sendKey(macKeyCode: UInt16, down: Bool) -> Bool {
        guard let xt = MacKeyMap.xtCode(forMacKeyCode: macKeyCode) else { return false }
        return sendKey(xtCode: xt, down: down)
    }

    @discardableResult
    public func sendKey(xtCode: UInt32, down: Bool) -> Bool {
        // keysym 0: QEMU derives the key from the scancode.
        (try? write(Self.extendedKeyEvent(down: down, keysym: 0, xtCode: xtCode))) != nil
    }

    /// Absolute pointer in framebuffer coordinates. `buttons`: 1 left, 2 middle, 4 right, 8 wheel up, 16 wheel down.
    @discardableResult
    public func sendPointer(x: Int, y: Int, buttons: UInt8) -> Bool {
        let (w, h) = framebufferSize
        let cx = max(0, min(x, max(0, w - 1))), cy = max(0, min(y, max(0, h - 1)))
        return (try? write(Self.pointerEvent(buttons: buttons, x: cx, y: cy))) != nil
    }

    private func requestUpdate(incremental: Bool) throws {
        let (w, h) = framebufferSize
        try write(Self.updateRequest(incremental: incremental, x: 0, y: 0, w: w, h: h))
    }

    // MARK: Read loop

    private func readLoop() {
        do {
            while true {
                let type = try readBytes(1)[0]
                switch type {
                case 0: try readFramebufferUpdate()
                case 1:                                    // SetColourMapEntries (unused with true colour)
                    _ = try readBytes(1); _ = try readU16()
                    let n = Int(try readU16()); _ = try readBytes(n * 6)
                case 2: break                              // Bell
                case 3:                                    // ServerCutText: ignored (clipboard sharing is not implemented)
                    _ = try readBytes(3)
                    let n = Int(try readU32())
                    guard n <= 1 << 20 else { throw RFBError.protocolError("cut text too large") }
                    _ = try readBytes(n)
                default: throw RFBError.protocolError("unknown server message \(type)")
                }
            }
        } catch {
            let wasClosed = lock.withLock { closed }
            close()
            onClose(wasClosed ? nil : (error as? RFBError) ?? .closed)
        }
    }

    private func readFramebufferUpdate() throws {
        _ = try readBytes(1)
        let rects = Int(try readU16())
        for _ in 0..<rects {
            let x = Int(try readU16()), y = Int(try readU16()), w = Int(try readU16()), h = Int(try readU16())
            let enc = Int32(bitPattern: try readU32())
            switch enc {
            case 0: try readRaw(x: x, y: y, w: w, h: h)
            case 1:
                let sx = Int(try readU16()), sy = Int(try readU16())
                try copyRect(sx: sx, sy: sy, x: x, y: y, w: w, h: h)
            case -223: try resize(width: w, height: h)
            case -258: lock.withLock { extendedKeyAck = true }
            default: throw RFBError.protocolError("unsupported encoding \(enc)")
            }
        }
        emit()
        try requestUpdate(incremental: true)
    }

    private func readRaw(x: Int, y: Int, w: Int, h: Int) throws {
        let bytes = w * h * 4
        guard bytes <= Self.maxRectBytes else { throw RFBError.protocolError("rect too large") }
        var buf = [UInt8](repeating: 0, count: bytes)
        try buf.withUnsafeMutableBytes { try readExact($0.baseAddress!, count: bytes) }
        try lock.withLock {
            guard x >= 0, y >= 0, x + w <= width, y + h <= height else { throw RFBError.protocolError("rect outside framebuffer") }
            for row in 0..<h {
                let dst = ((y + row) * width + x) * 4
                pixels.replaceSubrange(dst..<(dst + w * 4), with: buf[(row * w * 4)..<((row + 1) * w * 4)])
            }
        }
    }

    private func copyRect(sx: Int, sy: Int, x: Int, y: Int, w: Int, h: Int) throws {
        try lock.withLock {
            guard sx >= 0, sy >= 0, sx + w <= width, sy + h <= height, x >= 0, y >= 0, x + w <= width, y + h <= height
            else { throw RFBError.protocolError("copyrect outside framebuffer") }
            var tmp = [UInt8](); tmp.reserveCapacity(w * h * 4)
            for row in 0..<h { let s = ((sy + row) * width + sx) * 4; tmp += pixels[s..<(s + w * 4)] }
            for row in 0..<h { let d = ((y + row) * width + x) * 4; pixels.replaceSubrange(d..<(d + w * 4), with: tmp[(row * w * 4)..<((row + 1) * w * 4)]) }
        }
    }

    private func resize(width w: Int, height h: Int) throws {
        guard w > 0, h > 0, w <= Self.maxDimension, h <= Self.maxDimension, w * h * 4 <= Self.maxRectBytes
        else { throw RFBError.protocolError("bad framebuffer size \(w)x\(h)") }
        lock.withLock { width = w; height = h; pixels = [UInt8](repeating: 0, count: w * h * 4) }
    }

    // MARK: Frames (throttled to ~60 per second)

    private func emit() {
        let now = DispatchTime.now()
        let due = lock.withLock { () -> Bool in
            if now.uptimeNanoseconds &- lastEmit.uptimeNanoseconds >= 16_000_000 { lastEmit = now; return true }
            if !emitScheduled { emitScheduled = true }
            return false
        }
        if due { deliver(); return }
        emitQueue.asyncAfter(deadline: .now() + .milliseconds(16)) { [self] in
            let go = lock.withLock { () -> Bool in let s = emitScheduled; emitScheduled = false; lastEmit = .now(); return s }
            if go { deliver() }
        }
    }

    private func deliver() {
        let snap: (Int, Int, Data)? = lock.withLock { width > 0 ? (width, height, Data(pixels)) : nil }
        guard let (w, h, data) = snap, let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return }
        onFrame(RFBFrame(width: w, height: h, image: image))
    }

    // MARK: Socket helpers

    private func write(_ bytes: [UInt8]) throws {
        writeLock.lock(); defer { writeLock.unlock() }
        var sent = 0
        while sent < bytes.count {
            let n = bytes.withUnsafeBytes { Darwin.write(fd, $0.baseAddress! + sent, bytes.count - sent) }
            if n <= 0 { if n < 0 && errno == EINTR { continue }; throw RFBError.closed }
            sent += n
        }
    }

    private func readExact(_ ptr: UnsafeMutableRawPointer, count: Int) throws {
        var got = 0
        while got < count {
            let n = Darwin.read(fd, ptr + got, count - got)
            if n == 0 { throw RFBError.closed }
            if n < 0 { if errno == EINTR { continue }; throw RFBError.closed }
            got += n
        }
    }

    private func readBytes(_ n: Int) throws -> [UInt8] {
        var b = [UInt8](repeating: 0, count: n)
        if n > 0 { try b.withUnsafeMutableBytes { try readExact($0.baseAddress!, count: n) } }
        return b
    }

    private func readU16() throws -> UInt16 { let b = try readBytes(2); return UInt16(b[0]) << 8 | UInt16(b[1]) }
    private func readU32() throws -> UInt32 { let b = try readBytes(4); return b.reduce(UInt32(0)) { $0 << 8 | UInt32($1) } }
}
