# Releasing NexVM (signed and notarized)

Releases are built on the maintainer's Mac with an Apple Developer ID. Nothing secret lives in this repository:
the signing identity comes from the Keychain and the notarization credentials from a `notarytool` keychain profile.

## One-time setup
1. A **Developer ID Application** certificate in the login Keychain (`security find-identity -v -p codesigning`).
2. Notarization credentials stored in the Keychain (asks for an app-specific password from appleid.apple.com):
   ```bash
   xcrun notarytool store-credentials nexvm-notary --apple-id <apple-id> --team-id <team-id>
   ```

## Build a release
```bash
export NEXVM_SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)"
# optional: export NEXVM_NOTARY_PROFILE=nexvm-notary
scripts/release.sh            # build/NexVM-<version>.dmg + .sha256 (signed, notarized, stapled)
```
`NEXVM_SKIP_NOTARIZE=1 scripts/release.sh` signs and builds the DMG without notarizing (dry run; Gatekeeper warns).

## Publish
```bash
gh release create v<version> build/NexVM-<version>.dmg build/NexVM-<version>.dmg.sha256 \
  --title "NexVM <version>" --notes-file <notes.md> --prerelease
```
The website (`site/`, deployed by `.github/workflows/pages.yml` to nexvm.gbsoficial.com) links to the latest release.

## What the signature exposes
A Developer ID signature carries the certificate holder's name and Team ID; anyone can read it with `codesign -dv` and
Gatekeeper shows it. Use an identity you are comfortable making public (an organization account if available).
