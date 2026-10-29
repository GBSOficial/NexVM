# Contributing
1. Requirements: Apple Silicon Mac, Xcode (Swift 6 toolchain). `swift build && swift test` must pass.
2. Read `CLAUDE.md` (architecture and code rules) and `docs/decisions/`.
3. Small PRs, Conventional Commits, tests for behavior changes, docs updated. UI text goes through `L("key")` in all three `.strings` files.
4. No VM disks, ISOs, firmware, keys or secrets in commits. Never claim a guest "works" without evidence in `docs/compatibility/`.
5. Security issues: see `SECURITY.md`.
