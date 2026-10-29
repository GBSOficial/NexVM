import SwiftUI
import AppKit
import NexVMDisplay

/// Draws the guest framebuffer (aspect-fit) and forwards keyboard and mouse to the VM.
/// Keys travel as physical scancodes, so the guest's own keyboard layout decides the characters.
final class DisplayNSView: NSView {
    weak var session: DisplaySession?
    private var pressedKeys = Set<UInt16>()
    private var buttons: UInt8 = 0
    private var imageSize = CGSize.zero

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .trilinear
        setAccessibilityRole(.group)
        setAccessibilityLabel(L("a11y.display"))
    }
    required init?(coder: NSCoder) { fatalError("not used") }

    func setImage(_ image: CGImage?) {
        layer?.contents = image
        imageSize = image.map { CGSize(width: $0.width, height: $0.height) } ?? .zero
    }

    // MARK: Focus

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.acceptsMouseMovedEvents = true
    }

    override func resignFirstResponder() -> Bool {
        releaseEverything()
        return super.resignFirstResponder()
    }

    private func releaseEverything() {
        for k in pressedKeys { session?.sendKey(macKeyCode: k, down: false) }
        pressedKeys.removeAll()
        if buttons != 0, let p = lastPoint { session?.sendPointer(x: p.0, y: p.1, buttons: 0) }
        buttons = 0
    }

    // MARK: Keyboard

    override func keyDown(with event: NSEvent) {
        guard !event.isARepeat else { return }          // the guest generates its own auto-repeat
        pressedKeys.insert(event.keyCode)
        session?.sendKey(macKeyCode: event.keyCode, down: true)
    }

    override func keyUp(with event: NSEvent) {
        pressedKeys.remove(event.keyCode)
        session?.sendKey(macKeyCode: event.keyCode, down: false)
    }

    /// Menu shortcuts (⌘Q, ⌘W, …) stay with macOS; Control combinations belong to the guest.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) { return false }
        if event.modifierFlags.contains(.control), window?.firstResponder === self {
            if event.type == .keyDown { keyDown(with: event) } else { keyUp(with: event) }
            return true
        }
        return false
    }

    /// Device-dependent modifier bits (NX_DEVICE*KEYMASK) tell left from right.
    private static let modifierBits: [UInt16: UInt] = [
        0x38: 0x02, 0x3C: 0x04, 0x3B: 0x01, 0x3E: 0x2000, 0x3A: 0x20, 0x3D: 0x40, 0x37: 0x08, 0x36: 0x10,
    ]

    override func flagsChanged(with event: NSEvent) {
        let code = event.keyCode
        if code == 0x39 {                                // Caps Lock toggles: send a press+release pulse
            session?.sendKey(macKeyCode: code, down: true)
            session?.sendKey(macKeyCode: code, down: false)
            return
        }
        guard let bit = Self.modifierBits[code] else { return }
        let down = (event.modifierFlags.rawValue & bit) != 0
        if down { pressedKeys.insert(code) } else { pressedKeys.remove(code) }
        session?.sendKey(macKeyCode: code, down: down)
    }

    // MARK: Mouse

    private var lastPoint: (Int, Int)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for t in trackingAreas { removeTrackingArea(t) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil))
    }

    /// Window point → framebuffer pixel, honouring the aspect-fit letterbox. nil when outside the image.
    private func framebufferPoint(_ event: NSEvent, clamp: Bool) -> (Int, Int)? {
        guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return nil }
        let p = convert(event.locationInWindow, from: nil)
        let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        let ox = (bounds.width - w) / 2, oy = (bounds.height - h) / 2
        var x = (p.x - ox) / scale, y = (p.y - oy) / scale
        if !clamp && (x < 0 || y < 0 || x >= imageSize.width || y >= imageSize.height) { return nil }
        x = max(0, min(x, imageSize.width - 1)); y = max(0, min(y, imageSize.height - 1))
        return (Int(x), Int(y))
    }

    private func pointer(_ event: NSEvent, clamp: Bool = false) {
        guard let p = framebufferPoint(event, clamp: clamp || buttons != 0) else { return }
        lastPoint = p
        session?.sendPointer(x: p.0, y: p.1, buttons: buttons)
    }

    private func setButton(_ bit: UInt8, down: Bool, _ event: NSEvent) {
        if down { buttons |= bit } else { buttons &= ~bit }
        pointer(event, clamp: true)
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self); setButton(1, down: true, event) }
    override func mouseUp(with event: NSEvent) { setButton(1, down: false, event) }
    override func rightMouseDown(with event: NSEvent) { setButton(4, down: true, event) }
    override func rightMouseUp(with event: NSEvent) { setButton(4, down: false, event) }
    override func otherMouseDown(with event: NSEvent) { setButton(2, down: true, event) }
    override func otherMouseUp(with event: NSEvent) { setButton(2, down: false, event) }
    override func mouseMoved(with event: NSEvent) { pointer(event) }
    override func mouseDragged(with event: NSEvent) { pointer(event) }
    override func rightMouseDragged(with event: NSEvent) { pointer(event) }
    override func otherMouseDragged(with event: NSEvent) { pointer(event) }

    private var scrollAccumulator: CGFloat = 0

    override func scrollWheel(with event: NSEvent) {
        guard let p = framebufferPoint(event, clamp: true) else { return }
        scrollAccumulator += event.hasPreciseScrollingDeltas ? event.scrollingDeltaY / 10 : event.scrollingDeltaY
        while abs(scrollAccumulator) >= 1 {
            let wheel: UInt8 = scrollAccumulator > 0 ? 8 : 16      // RFB buttons 4 (up) and 5 (down)
            session?.sendPointer(x: p.0, y: p.1, buttons: buttons | wheel)
            session?.sendPointer(x: p.0, y: p.1, buttons: buttons)
            scrollAccumulator += scrollAccumulator > 0 ? -1 : 1
        }
    }
}

struct EmbeddedDisplayView: NSViewRepresentable {
    let session: DisplaySession

    func makeNSView(context: Context) -> DisplayNSView {
        let v = DisplayNSView()
        v.session = session
        return v
    }

    func updateNSView(_ view: DisplayNSView, context: Context) {
        view.session = session
        view.setImage(session.image)        // reading `image` makes SwiftUI call this again on every new frame
    }
}
