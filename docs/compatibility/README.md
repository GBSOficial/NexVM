# Compatibility matrix

A guest is **Tested** only after: real boot, install, reboot with data kept, and basic keyboard/mouse interaction, with evidence recorded here. A running QEMU process or a black window is not evidence.

| Guest | Status | Evidence |
|---|---|---|
| Linux ARM64 | Planned | none yet |
| Windows 11 ARM64 | Planned | none yet |
| Windows App Mode | Planned (design only) | — |

## Phase 0 host facts (measured 2026-10-29)
- Apple M4, 10 cores, 16 GiB RAM, macOS 27.0.1, Xcode 27.1, Swift 6.4, `kern.hv_support=1`.
- QEMU not installed. Homebrew formula: qemu 11.1.2, GPL-2.0-only, 15 dependencies.

## Unit-tested (no guest involved)
QEMU argument construction, QMP parsing, process lifecycle (SIGTERM→SIGKILL on own pid), VM bundle persistence, path validation, resource limits. These do **not** prove any guest boots.
