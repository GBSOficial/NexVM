# ADR-0001 — Single SwiftPM package at repository root

Status: accepted (2026-10-29)

## Context
The initial proposal listed `app/` + `packages/*` with an Xcode project. Xcode 27.1 / Swift 6.4 are installed, but no Xcode-project generator is, and a hand-maintained `.pbxproj` is merge-hostile for contributors.

## Decision
One root `Package.swift` with library targets (`NexVMCore`, `NexVMStorage`, `NexVMEngine`, `NexVMQEMU`, `NexVMDiagnostics`) and an executable target `NexVMApp`. `scripts/package-app.sh` assembles `NexVM.app` (Info.plist, resource bundle, ad-hoc signature). Targets that would be empty (Networking, Display, GuestIntegration, Updater) are not created until they hold real code.

## Consequences
- `swift build` / `swift test` work with only Xcode command line tools; no paid Apple account needed to build and run locally.
- No `.xcodeproj` yet. If entitlements, asset catalogs or Sparkle-style updating need it, add an Xcode project that depends on this package (new ADR).
- Test coverage and module boundaries are enforced by SwiftPM target dependencies.
