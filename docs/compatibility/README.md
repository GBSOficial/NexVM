# Compatibility matrix

A guest is **Tested** only after: real boot, install, reboot with data kept, and basic keyboard/mouse interaction, with evidence recorded here. A running QEMU process or a black window is not evidence.

| Guest | Status | Evidence |
|---|---|---|
| Linux ARM64 | Planned | none yet |
| Windows 11 ARM64 | Planned | none yet |
| Windows App Mode | Planned (design only) | — |

## Phase 0 host facts (measured 2026-10-29)
- Apple M4, 10 cores, 16 GiB RAM, macOS 27.0.1, Xcode 27.1, Swift 6.4, `kern.hv_support=1`.
- QEMU 11.1.3 installed 2026-10-29 in a separate Homebrew prefix on the SSD (`/path/to/tools/homebrew`, Tier 3, built in ~3 min). Nothing installed in `/opt/homebrew`.
- Verified: `qemu-system-aarch64 --version`, `-accel help` lists `hvf`, `edk2-aarch64-code.fd` present, and `-machine virt -accel hvf -cpu host -display none -S` starts and stays alive (no guest ran).
- `swtpm` is NOT installed: Windows 11 TPM path unresolved.

## Integration evidence (2026-10-29, `EngineIntegrationTests`, real QEMU 11.1.3 + HVF)
- `QEMUEngine` starts a VM with no OS media, connects QMP, reports `running`; UEFI (edk2) banner appears on the serial console, proving firmware executed under HVF.
- A second start of the same VM is rejected; `forceStop` ends only that process; lock is released; NVRAM (`metadata/vars.fd`) persists and a second boot works.
- Found by this test: `-name ...,process=` is unsupported on macOS (removed).
- No guest OS has been installed or booted yet.

## Unit-tested (no guest involved)
QEMU argument construction, QMP parsing, process lifecycle (SIGTERM→SIGKILL on own pid), VM bundle persistence, path validation, resource limits. These do **not** prove any guest boots.
