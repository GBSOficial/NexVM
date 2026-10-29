#!/usr/bin/env bash
# Builds a signed, notarized, stapled NexVM-<version>.dmg in build/.
#
# One-time setup on the release machine (credentials stay in your Keychain, never in this repo):
#   xcrun notarytool store-credentials nexvm-notary --apple-id <apple-id> --team-id <team-id>
#   (it asks for an app-specific password from appleid.apple.com)
#
# Usage:
#   export NEXVM_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)"
#   [export NEXVM_NOTARY_PROFILE=nexvm-notary]        # keychain profile name (default: nexvm-notary)
#   [export NEXVM_SKIP_NOTARIZE=1]                    # sign + DMG only, for a dry run
#   scripts/release.sh
set -euo pipefail

: "${NEXVM_SIGN_IDENTITY:?set NEXVM_SIGN_IDENTITY to your Developer ID Application identity}"
PROFILE="${NEXVM_NOTARY_PROFILE:-nexvm-notary}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(cat "$ROOT/VERSION")"
APP="$ROOT/build/NexVM.app"
DMG="$ROOT/build/NexVM-$VERSION.dmg"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

cd "$ROOT"
python3 scripts/check-strings.py
NEXVM_SIGN_IDENTITY="$NEXVM_SIGN_IDENTITY" scripts/package-app.sh release

cp -R "$APP" "$STAGE/NexVM.app"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "NexVM $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --timestamp --sign "$NEXVM_SIGN_IDENTITY" "$DMG"

if [ "${NEXVM_SKIP_NOTARIZE:-0}" = "1" ]; then
  echo "Dry run: $DMG signed but NOT notarized (Gatekeeper will warn)."
  exit 0
fi

xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
( cd build && shasum -a 256 "NexVM-$VERSION.dmg" > "NexVM-$VERSION.dmg.sha256" )
echo "Release ready: $DMG"
cat "build/NexVM-$VERSION.dmg.sha256"
