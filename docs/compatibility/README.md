# Compatibility matrix

A guest is **Tested** only after: real boot, install, reboot with data kept, and basic keyboard/mouse interaction, with evidence recorded here. A running QEMU process or a black window is not evidence.

| Guest | Status | Evidence |
|---|---|---|
| Linux ARM64 | **Tested (Alpine 3.24.3 only)** — live ISO boots; installs to the NexVM disk; reboots from disk with data kept; ACPI shutdown works. Mouse unverified (text console); graphical desktop guest untested | see below |
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

## Linux ARM64 install/reboot evidence (2026-10-29, Alpine virt 3.24.3, 2 vCPU / 2 GiB, raw sparse 32 GiB disk in a NexVM bundle)
- Keyboard: in the QEMU window, typing with held keys (`hold_key`, 80 ms) delivered `root` intact to the guest login. Zero-duration synthetic key events dropped characters (`root` → `ot`); that is a property of the injector, not evidence of a NexVM bug. The GUI login itself was refused by the live image on `/dev/tty0`/`tty1` (cause not investigated); root login works on the serial console.
- Install: `setup-alpine` with an answer file (`-m sys /dev/vda`) driven over the serial console (`tools/alpine-serial-install.py`, same QEMU arguments as `QEMUCommandBuilder`) finished with exit 0 in <45 s.
- Finding 1 (guest installer): Alpine did not register a UEFI boot entry nor fill `EFI/BOOT/BOOTAA64.EFI`; the VM fell into the UEFI shell. Workaround used: copy `EFI/alpine/grubaa64.efi` to `EFI/boot/bootaa64.efi`. (Windows installers create their own entries.)
- Finding 2 (NexVM, fixed): without `bootindex` on the disk the firmware did not list it once the ISO was detached. The primary disk now gets `bootindex=1`.
- Reboot from disk, no ISO: banner `nexvm login:` (hostname of the installed system, kernel 6.18.59 vs live 6.18.58), `acpid` started; `/root/nexvm-marker` written before the reboot read back `nexvm-persist-ok`.
- `testInstalledAlpineBootsFromDiskAndShutsDownGracefully` (needs `NEXVM_TEST_INSTALLED_BUNDLE`): engine boots from disk, `requestShutdown` (ACPI) leads to `.stopped` (not `.error`) in ~17 s.
- NexVM UI: "Eject Install ISO" detaches media (config persisted, ISO file untouched).
- The app-launched QEMU window for the disk boot could not be captured by the screenshot tool (non-frontmost QEMU windows are filtered), so that boot was verified by serial/engine, not visually in the GUI.

## UI verification (2026-10-29, manual, dark and light)
Library cards, empty state, 4-step wizard with a real ISO, VM window, Settings (5 tabs), Diagnostics, delete confirmation, quit-with-running-VM (cancel keeps VM; confirm stops QEMU, no orphan), minimum window size reflow. Not checked: VoiceOver, Full Keyboard Access, multi-monitor/Split View, larger text sizes.

## Unit-tested (no guest involved)
QEMU argument construction, QMP parsing, process lifecycle (SIGTERM→SIGKILL on own pid), VM bundle persistence, path validation, resource limits. These do **not** prove any guest boots.
