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

# App icon: build AppIcon.icns from the committed appiconset (SwiftPM does not run actool for app icons).
ICONSET="$(mktemp -d)/AppIcon.iconset"
mkdir -p "$ICONSET"
SRC_ICONS="$ROOT/Sources/NexVMApp/Resources/Assets.xcassets/AppIcon.appiconset"
for s in 16x16 32x32 128x128 256x256 512x512; do
  cp "$SRC_ICONS/icon_${s}@1x.png" "$ICONSET/icon_${s}.png"
  cp "$SRC_ICONS/icon_${s}@2x.png" "$ICONSET/icon_${s}@2x.png"
done
iconutil -c icns "$ICONSET" -o "$OUT/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>org.nexvm.app</string>
  <key>CFBundleName</key><string>NexVM</string>
  <key>CFBundleDisplayName</key><string>NexVM</string>
  <key>CFBundleExecutable</key><string>NexVM</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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
