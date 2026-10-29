#!/usr/bin/env bash
# Builds NexVM.app from the SwiftPM executable. Ad-hoc signed: runs locally, NOT notarized.
# Usage: scripts/package-app.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/NexVM.app"
VERSION="$(cat "$ROOT/VERSION")"

cd "$ROOT"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN_DIR/NexVM" "$OUT/Contents/MacOS/NexVM"
cp -R "$BIN_DIR/NexVM_NexVMApp.bundle" "$OUT/Contents/Resources/"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>org.nexvm.app</string>
  <key>CFBundleName</key><string>NexVM</string>
  <key>CFBundleDisplayName</key><string>NexVM</string>
  <key>CFBundleExecutable</key><string>NexVM</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${VERSION}</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>pt-BR</string><string>pt-PT</string></array>
</dict></plist>
PLIST

codesign --force --sign - "$OUT"
echo "Built $OUT (ad-hoc signed, not notarized)"
