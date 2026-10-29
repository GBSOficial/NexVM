# ADR-0005 — Embedded display via VNC on a private unix socket

Status: accepted (2026-10-29), verified with Alpine and the Windows 11 ARM64 installer.

## Context
`-display cocoa` opens a QEMU-owned window: small, separate from NexVM, with its own mouse grab, and not controllable from the app. QEMU on macOS offers `none`, `curses`, `cocoa` and `dbus` display backends (no SPICE/GL here).

## Decision
Run QEMU with `-display none -vnc unix:<private dir>/vnc.sock` and draw the framebuffer in the VM window with an in-process RFB 3.8 client (`NexVMDisplay`). Security: the socket lives in a 0700 temp directory, no TCP port is opened, no password (local, same user). Encodings: Raw, CopyRect, DesktopSize (local socket, so bandwidth is not a concern). Keyboard uses QEMU's extended key event (physical XT scancodes from macOS key codes) so the guest's layout decides characters; ⌘ maps to the Windows key, ⌥ to Alt. Pointer is absolute (usb-tablet), wheel via buttons 4/5. A user setting (Settings → Advanced) falls back to QEMU's window.

## Consequences
- Full screen, Ctrl-Alt-Del, scaling and focus are handled by NexVM; no mouse capture needed.
- Resolution is the guest's (virtio-gpu showed 1280×800 over VNC; Windows with `ramfb` keeps the firmware mode). Dynamic resize needs a guest GPU driver and RFB ExtendedDesktopSize/SetDesktopSize, not implemented.
- Not implemented: clipboard sharing (ServerCutText is read and ignored), audio, host cursor shape, compressed encodings (ZRLE/Tight).
- Hardware cursor of the guest is not drawn; the macOS cursor is used.
