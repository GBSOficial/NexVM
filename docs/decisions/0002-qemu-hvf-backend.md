# ADR-0002 — QEMU (aarch64, HVF) as the first backend

Status: accepted for Phase 1–3; **unvalidated on this machine until QEMU is installed and a guest boots** (see `docs/compatibility/`).

## Options
| Option | Windows 11 ARM64 guest | Notes |
|---|---|---|
| Apple Virtualization.framework | Not an officially supported guest (supported: macOS, Linux) | Excellent Swift integration for Linux/macOS guests; would be a second backend for Linux later |
| Hypervisor.framework directly | Possible in theory | Would mean writing a VMM and device models; rejected ("do not reinvent a hypervisor") |
| QEMU `qemu-system-aarch64 -accel hvf` | Used by existing projects for Windows ARM; requires UEFI (edk2), and TPM via swtpm for Win11 | GPL-2.0; runs as a separate process |

## Decision
Use QEMU with HVF, behind the `VirtualMachineEngine` protocol so a Virtualization.framework backend can be added without touching UI/Core.

## Machine model (builder output, covered by unit tests, not yet booted)
`-machine virt -accel hvf -cpu host`, edk2 AArch64 pflash firmware, `ramfb` + xHCI keyboard/tablet, NVMe disk and e1000e NIC for Windows (inbox drivers), virtio-blk/virtio-net for Linux, user-mode NAT without port forwards, QMP on a unix socket, optional `tpm-tis-device` when an swtpm socket is provided.

## Open risks
- QEMU not installed here; `kern.hv_support=1` confirmed on the M4 host only.
- Windows 11 TPM/Secure Boot requirements: swtpm availability and packaging unverified.
- `-display cocoa` opens a QEMU-owned window; embedding display is future work.
- Performance: no measurements exist; none may be claimed.
