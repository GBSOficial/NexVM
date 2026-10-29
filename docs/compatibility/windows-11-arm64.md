# Windows 11 ARM64 — status and plan

**Status: Planned. No Windows install has been attempted. Nothing below is evidence of Windows working.**

## What NexVM already implements (unit-tested, not booted with Windows)
- Machine: `virt`, HVF, `-cpu host`, edk2 AArch64 UEFI, `ramfb` + xHCI keyboard/tablet.
- Disk as NVMe (inbox driver), NIC as `e1000e`, user-mode NAT without port forwards.
- Per-VM TPM 2.0 via `swtpm` (state in `metadata/tpm`, control socket in a private temp dir, `--terminate` so it dies with QEMU). The engine **refuses to start** a Windows VM when `swtpm` is not found; the UI shows why and the wizard warns early.
- "Eject Install ISO" so the VM can boot from disk after Setup.

## Requirements (user side)
1. Windows 11 ARM64 ISO downloaded by you from Microsoft (<https://www.microsoft.com/software-download/windows11arm64>). NexVM never downloads, bundles or redistributes it.
2. A valid Windows license. NexVM provides no keys and no activation workarounds.
3. `swtpm` installed next to QEMU (installed on this machine, SSD prefix, 2026-10-29; see below).
4. Recommended starting point on a 16 GB Mac: 4 vCPU, 4 GB RAM, 64 GB disk (the wizard defaults). Adjust after measuring.

## TPM evidence (2026-10-29, swtpm 0.10.2 + QEMU 11.1.3, no Windows involved)
- `testWindowsVMStartsSwtpmAndCleansUp`: a Windows-type VM started through the engine launches swtpm, connects it to QEMU, runs the UEFI firmware under HVF, creates TPM state in `metadata/tpm`, and no swtpm process survives after Force Stop.
- Finding: `tpm-tis-device` with its default PPI region fails under HVF on Apple Silicon (`HV_BAD_ARGUMENT`, 1 KB RAM region vs 16 KB host pages). NexVM uses `ppi=off`. Consequence: no TPM Physical Presence Interface (firmware/OS "clear TPM" requests); not needed for installing Windows, effect on other flows unknown.
- Guest view (Alpine, serial): the kernel log shows `TPMEventLog`/`TPMFinalLog` (firmware measured boot reached the TPM) and an ACPI `TPM2` table. The Alpine `virt` kernel has no TIS driver, so no `/dev/tpm0`; that says nothing about Windows.

## Unverified assumptions (each must be tested before claiming support)
| Item | Why it matters |
|---|---|
| Windows Setup accepts the swtpm TPM 2.0 | Win11 requirement check |
| Secure Boot | The stock `edk2-aarch64-code.fd` has no enrolled Secure Boot keys; whether Setup on ARM64 requires "Secure Boot capable" is unconfirmed. No bypass will be implemented. |
| `e1000e` has an inbox Windows ARM64 driver | If not, no network during Setup/OOBE until a driver is supplied |
| `ramfb` resolution/performance | Fixed framebuffer, no accelerated graphics; Windows ARM guest drivers (e.g. virtio-gpu) are not redistributable by NexVM |
| NVMe boot, reboot with persisted data | Needs a real install |
| Clean shutdown via ACPI power button | Needs Windows running |
| Keyboard/mouse (usb-kbd, usb-tablet) | Needs Windows running |
| x64 app compatibility | Depends on Windows' own emulation layer; not promised |

## Acceptance (to mark "Tested")
Boot Setup from the official ISO → install → reboot from disk with data kept → keyboard and mouse work → ACPI shutdown → evidence (screenshots/log) recorded here. A running QEMU process or a black window is not evidence.

## swtpm install notes
Installed from Homebrew core formula `swtpm` 0.10.2 (BSD-3-Clause) + `libtpms` 0.10.2 (BSD-2-Clause), into the SSD prefix. The dry run lists 20 extra dependencies (mostly graphics libraries pulled in by `json-glib` → `gobject-introspection`); all official homebrew-core formulae. No telemetry (Homebrew analytics disabled); swtpm runs locally and opens only unix sockets.
