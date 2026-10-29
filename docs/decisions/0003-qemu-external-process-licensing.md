# ADR-0003 — QEMU runs as a separate process; NexVM code stays MIT

Status: accepted

## Decision
NexVM source is MIT. QEMU (GPL-2.0-only per Homebrew metadata; individual QEMU files carry other licenses) is **never linked** into NexVM; it is located on disk (`QEMUBinaryLocator`) and executed as a child process with structured arguments. Communication is via command line and QMP (JSON over a unix socket).

## Consequences
- Installing QEMU via Homebrew leaves GPL obligations with the QEMU distribution, not with NexVM.
- **Bundling QEMU inside NexVM.app is not decided.** If done, we must ship QEMU's license texts, provide corresponding source (or a written offer) for the exact binaries, and inventory every dynamic dependency (glib, gnutls, etc.; 15 Homebrew deps at 11.1.2). Needs its own ADR and legal review before any release.
- Firmware (edk2) is BSD-2-Clause-Patent-based but redistribution terms must be checked per file before bundling. Windows ISOs, drivers (virtio-win) and keys are never redistributed.
- Inventory lives in `NOTICE`.
