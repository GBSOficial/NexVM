# NexVM brand assets

Copied from the NexVM Brand Kit (identity board, app icon, logos, guide). Originals are kept untouched in `source/` and `logos/`.

- **Limits you must know:** the identity board was generated as a single image. `source/NexVM_Icon_Source_257px.png` is the real source (~257 px); `NexVM_Icon_1024.png` is an upscale, not a native master. SVGs in `logos/` are approximate vector rebuilds, not exact traces. Before a public release, redraw the icon at a native 1024 px.
- **App icon pipeline:** `scripts/make-app-icon.py` masks the 1024 master to a macOS-style rounded square with transparent margin and writes `Sources/NexVMApp/Resources/Assets.xcassets/AppIcon.appiconset`. `scripts/package-app.sh` turns that set into `AppIcon.icns` (SwiftPM does not run actool for app icons).
- **In-app logos:** `NexVMSymbol` and `NexVMHorizontal` (light/dark variants) imagesets in the same catalog use the PNG exports.
- **Tokens:** `Sources/NexVMApp/Design/NexVMTheme.swift` (from `colors.json`). See `BRAND_GUIDE.md`.
