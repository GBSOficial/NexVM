import Foundation
import CoreGraphics
import Observation
import NexVMDisplay

/// Connection between one VM window and the VM's VNC display. Lives on the main actor; the RFB
/// client calls back from its own threads and results are hopped over here.
@MainActor
@Observable
final class DisplaySession {
    enum Status: Equatable { case idle, connecting, connected, failed(String) }

    private(set) var status: Status = .idle
    private(set) var image: CGImage?
    private var client: RFBClient?
    private var generation = 0

    func connect(socketPath: String) async {
        disconnect()
        generation += 1
        let gen = generation
        status = .connecting
        do {
            let c = try await RFBClient.connect(
                path: socketPath, timeout: 10,
                onFrame: { [weak self] frame in
                    Task { @MainActor in
                        guard let self, self.generation == gen else { return }
                        self.image = frame.image
                    }
                },
                onClose: { [weak self] error in
                    Task { @MainActor in
                        guard let self, self.generation == gen else { return }
                        self.client = nil
                        self.status = error == nil ? .idle : .failed("\(error!)")
                    }
                })
            guard generation == gen else { c.close(); return }
            client = c
            status = .connected
        } catch {
            guard generation == gen else { return }
            status = .failed("\(error)")
        }
    }

    func disconnect() {
        generation += 1
        client?.close()
        client = nil
        image = nil
        status = .idle
    }

    func sendKey(macKeyCode: UInt16, down: Bool) { client?.sendKey(macKeyCode: macKeyCode, down: down) }
    func sendKey(xtCode: UInt32, down: Bool) { client?.sendKey(xtCode: xtCode, down: down) }
    func sendPointer(x: Int, y: Int, buttons: UInt8) { client?.sendPointer(x: x, y: y, buttons: buttons) }

    /// Ctrl+Alt+Del cannot be typed on a Mac keyboard, so it gets its own command.
    func sendCtrlAltDel() async {
        let keys = [MacKeyMap.leftControl, MacKeyMap.leftAlt, MacKeyMap.delete]
        for k in keys { sendKey(xtCode: k, down: true); try? await Task.sleep(for: .milliseconds(40)) }
        try? await Task.sleep(for: .milliseconds(80))
        for k in keys.reversed() { sendKey(xtCode: k, down: false); try? await Task.sleep(for: .milliseconds(40)) }
    }
}
