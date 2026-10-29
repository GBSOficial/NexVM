# Changelog
## Unreleased
- Embedded VM display: QEMU serves VNC on a private unix socket; new `NexVMDisplay` RFB client; display, keyboard (physical scancodes), absolute mouse and scroll inside the VM window; Full Screen, Ctrl-Alt-Del, details inspector; Settings → Advanced to use QEMU's window instead.
- Windows 11 ARM64 installer boots and runs in NexVM (experimental).
- TPM: `tpm-tis-device,ppi=off` (HVF rejects the PPI region); swtpm lifecycle integration test.
- Windows 11 groundwork: per-VM swtpm TPM 2.0 management, Windows start blocked with a clear message when swtpm is missing, wizard warning, `docs/compatibility/windows-11-arm64.md`.
- Eject install ISO (VM window and context menu); primary disk gets `bootindex=1`; selecting the VM when started so the Virtual Machine menu works.
- Linux install/reboot evidence and `tools/alpine-serial-install.py`.
- Brand identity: app icon (`AppIcon.icns` built from the asset catalog), N symbol and horizontal logo, `NexVMTheme` tokens, Light/Dark support.
- New window layout: main window with sidebar (Virtual Machines, Diagnostics, Settings link), adaptive VM cards, 4-step creation wizard with per-step validation, separate VM window with Run/Shut Down/Restart/Force Stop, Settings scene (General, Hardware Defaults, Storage, Network, Advanced), Virtual Machine menu, ⌘N / ⌘R / ⌘I / ⌘,.
- Quitting with running VMs asks for confirmation and force-stops them (no orphan QEMU); closing windows does not stop VMs.
- Engine: `restart` (QMP system_reset), `activeVMIDs`.
- Phase 1 foundation: SwiftPM package, Core/Storage/Engine/QEMU/Diagnostics modules, SwiftUI library window (create/list/remove/delete; no VM start yet), en/pt-BR/pt-PT strings, 40 unit tests.
