# Windows App Mode — design notes (NOT implemented)

Goal: launch Windows programs from macOS with few clicks. Planned only after full-VM mode is proven (roadmap Phase 6).

Constraints, stated honestly:
- A `.exe` runs inside a Windows ARM64 guest; x64 programs depend on Windows' own emulation layer. No universal compatibility is promised. This is not Wine.
- No global `.exe` file association until there is a reliable launch flow with isolation and per-action user consent.
- Requires an optional guest agent (authenticated, host-initiated channel such as virtio-vsock/serial; protocol TBD), shared-folder consent UI, and window integration research.
- Each capability (clipboard, folders, window integration) ships as experimental until tested on a real guest.
