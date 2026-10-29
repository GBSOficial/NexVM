# NexVM — Your OS. Your Freedom.

An open-source virtual machine manager for Apple Silicon Macs, designed to make running Windows and Linux simple, accessible and free.

**Website and download: <https://nexvm.gbsoficial.com>** · [Releases](https://github.com/GBSOficial/NexVM/releases)

> **Status: preview (v0.1.0).** Linux ARM64 is tested (install, reboot from disk, ACPI shutdown). Windows 11 ARM64 is **experimental**: the official installer completes and the installed system reaches first-run setup; desktop, shutdown and network are not verified yet. See [compatibility](docs/compatibility/README.md). Nothing is claimed without a real test.

## What exists today
- SwiftUI app: VM library, create (name, OS, CPU, RAM, disk, optional ISO), start / shut down / restart / force stop, delete data with confirmation.
- Embedded display (QEMU over a private unix socket + built-in RFB client) with keyboard, mouse, scroll and full screen.
- QEMU aarch64 + HVF engine with QMP, per-VM TPM 2.0 (`swtpm`), per-VM UEFI firmware choice (standard / Secure Boot), per-VM network adapter (e1000e / VirtIO) and optional driver ISO.
- `.nexvm` bundle with versioned `config.json`, atomic writes, sparse raw disks, ISO structural check, per-VM lock.
- Local JSONL logs only. No telemetry, accounts or proprietary server.
- English, Português (Brasil) and Português (Portugal) UI.

## Planned
Clipboard, audio, dynamic resolution, snapshots, guest integration, Windows App Mode (design only, see [docs](docs/architecture/windows-app-mode.md)). Nothing here is promised until tested.

## Install (preview build)
1. Download the notarized `.dmg` from the [website](https://nexvm.gbsoficial.com) or [Releases](https://github.com/GBSOficial/NexVM/releases) and drag NexVM to Applications.
2. Install QEMU (not bundled): `brew install qemu swtpm`.
3. Create a VM with your own ISO. Windows ISOs come from Microsoft ([download](https://www.microsoft.com/software-download/windows11arm64)); you need a valid Windows license, and Windows 11 needs a Secure Boot UEFI firmware you install yourself ([details](docs/compatibility/windows-11-arm64.md)). NexVM does not redistribute or bypass anything.

Requirements: Apple Silicon Mac, macOS 14+ (developed and tested on macOS 27).

## Build from source
```bash
swift build
swift test
scripts/package-app.sh release   # build/NexVM.app — ad-hoc signed, NOT notarized
```
An unnotarized local build triggers Gatekeeper warnings; build locally or right-click → Open. Do not disable Gatekeeper system-wide. Maintainers: see [docs/releasing.md](docs/releasing.md) for signed and notarized releases. Machine-specific paths are configured with environment variables (`NEXVM_QEMU_PREFIX`, `NEXVM_FIRMWARE_DIR`, `NEXVM_TEST_ISO`, see [CLAUDE.md](CLAUDE.md)).

## Contributing / Security / License
[CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md) · MIT ([LICENSE](LICENSE)); third-party notes in [NOTICE](NOTICE). Português: [README.pt-BR.md](README.pt-BR.md).
