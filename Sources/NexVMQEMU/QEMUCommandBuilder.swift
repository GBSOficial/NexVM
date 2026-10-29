import Foundation
import NexVMCore
import NexVMStorage

public struct QEMULaunchSpec: Equatable, Sendable {
    public var executable: URL
    /// Structured argv. Never joined into a shell string.
    public var arguments: [String]
}

public struct QEMUFirmware: Equatable, Sendable {
    /// Read-only AArch64 UEFI code (edk2-aarch64-code.fd).
    public var code: URL
    /// Per-VM writable NVRAM copy (vars). Must live inside the VM bundle.
    public var vars: URL
    public init(code: URL, vars: URL) { self.code = code; self.vars = vars }
}

public enum QEMUBuildError: Error, Equatable, Sendable {
    case unsupportedArchitecture
    case unsupportedBackend
    case noDisks
}

public enum QEMUOption {
    /// QEMU treats `,` as an option separator; a literal comma must be doubled.
    public static func escape(_ value: String) -> String { value.replacingOccurrences(of: ",", with: ",,") }
}

public struct QEMUBuildOptions: Equatable, Sendable {
    /// No window; serial console goes to `serialLog` (used by automated boot tests).
    public var headless = false
    public var serialLog: URL?
    public init(headless: Bool = false, serialLog: URL? = nil) { self.headless = headless; self.serialLog = serialLog }
}

public struct QEMUCommandBuilder: Sendable {
    public var installation: QEMUInstallation

    public init(installation: QEMUInstallation) { self.installation = installation }

    /// - Parameters:
    ///   - qmpSocket: unix socket path for QMP (host-local, no TCP listener).
    ///   - tpmSocket: swtpm control socket; pass nil when no TPM emulator is available.
    public func build(
        configuration c: VMConfiguration,
        bundle: VMBundle,
        firmware: QEMUFirmware,
        qmpSocket: URL,
        tpmSocket: URL? = nil,
        options: QEMUBuildOptions = QEMUBuildOptions()
    ) throws -> QEMULaunchSpec {
        guard c.architecture == .arm64 else { throw QEMUBuildError.unsupportedArchitecture }
        guard c.backend == .qemu else { throw QEMUBuildError.unsupportedBackend }
        guard !c.disks.isEmpty else { throw QEMUBuildError.noDisks }
        let e = QEMUOption.escape

        var a: [String] = []
        a += ["-name", e(c.name)]  // `process=` is unsupported on macOS
        a += ["-nodefaults", "-no-user-config"]
        a += ["-machine", "virt", "-accel", "hvf", "-cpu", "host"]
        a += ["-smp", String(c.cpuCount), "-m", "\(c.memoryMiB)M"]

        a += ["-drive", "if=pflash,format=raw,unit=0,readonly=on,file=\(e(firmware.code.path))"]
        a += ["-drive", "if=pflash,format=raw,unit=1,file=\(e(firmware.vars.path))"]

        // Display and input. Windows has no inbox virtio-gpu driver, so it gets ramfb (UEFI
        // framebuffer). Linux gets virtio-gpu so the kernel console/desktop render after boot.
        a += ["-device", c.guest == .windows11ARM64 ? "ramfb" : "virtio-gpu-pci"]
        a += ["-device", "qemu-xhci", "-device", "usb-kbd", "-device", "usb-tablet"]

        for (i, disk) in c.disks.enumerated() {
            let path = try PathValidator.resolve(disk.relativePath, under: bundle.url)
            let id = "disk\(i)"
            a += ["-drive", "if=none,id=\(id),format=\(disk.format.rawValue),file=\(e(path.path))"]
            // The first disk gets bootindex=1 (install media keeps 0) so firmware lists it in the
            // boot order; without it UEFI falls back to its shell when no ISO is attached.
            let boot = i == 0 ? ",bootindex=1" : ""
            switch disk.interface {
            case .virtioBlk:
                a += ["-device", "virtio-blk-pci,drive=\(id)\(boot)"]
            case .nvme:
                a += ["-device", "nvme,drive=\(id),serial=nexvm\(i)\(boot)"]
            }
        }

        if let media = c.installMedia {
            a += ["-drive", "if=none,id=cd0,media=cdrom,readonly=on,file=\(e(media.path))"]
            a += ["-device", "usb-storage,drive=cd0,bootindex=0"]
        }

        switch c.network.mode {
        case .userNAT:
            // No hostfwd: nothing is exposed on host interfaces.
            a += ["-netdev", "user,id=net0"]
            // Windows has no inbox virtio-net driver; e1000e is inbox. Linux uses virtio.
            let nic = c.guest == .windows11ARM64 ? "e1000e" : "virtio-net-pci"
            a += ["-device", "\(nic),netdev=net0"]
        }

        if let tpm = tpmSocket {
            a += ["-chardev", "socket,id=chrtpm,path=\(e(tpm.path))"]
            a += ["-tpmdev", "emulator,id=tpm0,chardev=chrtpm"]
            // ppi=off: the PPI RAM region (1 KB) is not 16 KB-aligned and HVF on Apple Silicon rejects it (HV_BAD_ARGUMENT).
            a += ["-device", "tpm-tis-device,tpmdev=tpm0,ppi=off"]
        }

        a += ["-qmp", "unix:\(e(qmpSocket.path)),server=on,wait=off"]
        if let log = options.serialLog { a += ["-serial", "file:\(e(log.path))"] }
        // zoom-to-fit: the guest image scales with the window, so the (often small) guest framebuffer can be enlarged by resizing it.
        a += ["-display", options.headless ? "none" : "cocoa,zoom-to-fit=on,zoom-interpolation=on"]

        return QEMULaunchSpec(executable: installation.system, arguments: a)
    }
}
