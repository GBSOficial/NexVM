# Changelog
## Unreleased
- Brand identity: app icon (`AppIcon.icns` built from the asset catalog), N symbol and horizontal logo, `NexVMTheme` tokens, Light/Dark support.
- New window layout: main window with sidebar (Virtual Machines, Diagnostics, Settings link), adaptive VM cards, 4-step creation wizard with per-step validation, separate VM window with Run/Shut Down/Restart/Force Stop, Settings scene (General, Hardware Defaults, Storage, Network, Advanced), Virtual Machine menu, ⌘N / ⌘R / ⌘I / ⌘,.
- Quitting with running VMs asks for confirmation and force-stops them (no orphan QEMU); closing windows does not stop VMs.
- Engine: `restart` (QMP system_reset), `activeVMIDs`.
- Phase 1 foundation: SwiftPM package, Core/Storage/Engine/QEMU/Diagnostics modules, SwiftUI library window (create/list/remove/delete; no VM start yet), en/pt-BR/pt-PT strings, 40 unit tests.
