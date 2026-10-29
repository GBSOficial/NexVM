# NexVM — Your OS. Your Freedom.

An open-source virtual machine manager for Apple Silicon Macs, designed to make running Windows and Linux simple, accessible and free.

> **Status: early foundation (v0.1.0-dev).** NexVM can create and manage VM *bundles* but **cannot start a VM yet**. No guest OS has been booted. See [compatibility](docs/compatibility/README.md).

## What exists today
- SwiftUI app: VM library, create (name, OS, CPU, RAM, disk, optional ISO), remove from library, delete data with confirmation.
- `.nexvm` bundle with versioned `config.json`, atomic writes, sparse raw disks, ISO structural check, per-VM lock.
- QEMU aarch64/HVF command builder, QMP parser, safe child-process management (all unit-tested; none run against a real QEMU yet).
- Local JSONL logs (`~/Library/Logs/NexVM/nexvm.log`). No telemetry, accounts or network access.
- English, Português (Brasil) and Português (Portugal) UI.

## Planned
Linux ARM64 boot, Windows 11 ARM64 install flow, display/input, snapshots, guest integration, Windows App Mode (design only, see [docs](docs/architecture/windows-app-mode.md)). Nothing here is promised until tested.

## Requirements
Apple Silicon Mac, macOS 14+, Xcode with Swift 6. QEMU is installed separately (`brew install qemu`) and is not bundled. Windows ISOs come from Microsoft ([download](https://www.microsoft.com/software-download/windows11arm64)); you need a valid Windows license. NexVM does not redistribute or bypass anything.

## Build
```bash
swift build
swift test
scripts/package-app.sh release   # build/NexVM.app — ad-hoc signed, NOT notarized
```
An unnotarized app triggers Gatekeeper warnings; build locally or right-click → Open. Do not disable Gatekeeper system-wide.

## Contributing / Security / License
[CONTRIBUTING](CONTRIBUTING.md) · [SECURITY](SECURITY.md) · MIT ([LICENSE](LICENSE)); third-party notes in [NOTICE](NOTICE). Português: [README.pt-BR.md](README.pt-BR.md).
