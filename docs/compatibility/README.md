# Compatibility matrix

A guest is **Tested** only after: real boot, install, reboot with data kept, and basic keyboard/mouse interaction, with evidence recorded here. A running QEMU process or a black window is not evidence.

| Guest | Status | Evidence |
|---|---|---|
| Linux ARM64 | **Experimental** — Alpine virt 3.24.3 live ISO boots to `login:` (serial). Not installed to disk, no keyboard/mouse/display check yet | see below |
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
- `testAlpineBootsToLoginPrompt`: `alpine-virt-3.24.3-aarch64.iso` (sha256 e3460308…8f, verified against the official `latest-releases.yaml`) boots from the install-media path and reaches `login:` on the serial console in ~11 s, 2 vCPU / 1 GiB, virtio-blk + virtio-net, HVF. ISO stays unmodified.
- **GUI run (2026-10-29, manual via the app, Alpine live ISO):** New VM sheet → Start opens the QEMU window (TianoCore → GRUB → Alpine console `localhost login:`, kernel 6.18 aarch64, virtio-gpu); state shows Running; Force Stop returns to Stopped and closes the window. Shut Down sent ACPI and the state stayed "Shutting down" because the live ISO does not act on power-button events — Force Stop was needed.
- Keyboard: keystrokes reach the guest (login/password prompts respond) but synthetic fast typing dropped characters (`root` → `ot`). Not yet verified with real human typing; cause unknown. Mouse not verified.
- NOT shown: install to disk and reboot with persisted data, graphical display, keyboard/mouse input, clean ACPI shutdown. Windows has not been attempted.

## UI verification (2026-10-29, manual, dark and light)
Library cards, empty state, 4-step wizard with a real ISO, VM window, Settings (5 tabs), Diagnostics, delete confirmation, quit-with-running-VM (cancel keeps VM; confirm stops QEMU, no orphan), minimum window size reflow. Not checked: VoiceOver, Full Keyboard Access, multi-monitor/Split View, larger text sizes.

## Unit-tested (no guest involved)
QEMU argument construction, QMP parsing, process lifecycle (SIGTERM→SIGKILL on own pid), VM bundle persistence, path validation, resource limits. These do **not** prove any guest boots.
