#!/bin/bash
# Builds, signs (Developer ID), notarizes, staples, and zips a release.
#
# One-time setup:
#   1. Create a "Developer ID Application" certificate:
#      Xcode > Settings > Accounts > Manage Certificates > + > Developer ID Application
#   2. Store notarization credentials (uses an app-specific password from
#      appleid.apple.com; team ID is on developer.apple.com/account):
#      xcrun notarytool store-credentials granipa \
#        --apple-id YOUR_APPLE_ID --team-id YOUR_TEAM_ID
#
# Then: ./Scripts/release.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${NOTARY_PROFILE:-granipa}"
SIGN_ID="${CODESIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"

if [ -z "$SIGN_ID" ]; then
  echo "ERROR: no 'Developer ID Application' certificate found." >&2
  echo "Create one in Xcode > Settings > Accounts > Manage Certificates," >&2
  echo "or pass CODESIGN_ID explicitly." >&2
  exit 1
fi

VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
APP="build/Grañipa.app"
ZIP="build/Granipa-v$VERSION.zip"

echo "==> Building release (signing as: $SIGN_ID)"
CODESIGN_ID="$SIGN_ID" ./Scripts/bundle.sh release

echo "==> Verifying signature"
codesign --verify --strict --verbose=2 "$APP"

echo "==> Notarizing (profile: $PROFILE)"
rm -f "$ZIP"
# --sequesterRsrc keeps AppleDouble metadata out of the bundle: without it,
# Archive Utility extracts xattrs as literal ._ files inside Sparkle.framework,
# breaking the seal ("unsealed contents") and triggering Gatekeeper's malware dialog.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> Stapling ticket and producing final artifact"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

echo "==> Verifying the artifact survives Archive Utility (Finder double-click)"
RT="$(mktemp -d)"
cp "$ZIP" "$RT/" && open -W -a "Archive Utility" "$RT/$(basename "$ZIP")"
codesign --verify --deep --strict "$RT/$(basename "$APP")"
spctl --assess --type execute "$RT/$(basename "$APP")"
rm -rf "$RT"

echo
echo "Release artifact: $ZIP"
shasum -a 256 "$ZIP"

if [ "$(plutil -extract SUPublicEDKey raw "$APP/Contents/Info.plist" 2>/dev/null)" = "SPARKLE_ED_PUBLIC_KEY_PLACEHOLDER" ]; then
  echo
  echo "WARN: Sparkle public key not set — auto-updates will not verify."
  echo "      One-time setup: see docs/RELEASING.md"
fi

echo
if command -v generate_appcast >/dev/null 2>&1; then
  generate_appcast build/
  echo "Publish with:"
  echo "  gh release create v$VERSION '$ZIP' build/appcast.xml --title 'Grañipa v$VERSION' --generate-notes"
else
  echo "NOTE: generate_appcast not found — auto-update feed not generated."
  echo "      Get Sparkle's tools (one time): https://github.com/sparkle-project/Sparkle/releases"
  echo "Publish with:"
  echo "  gh release create v$VERSION '$ZIP' --title 'Grañipa v$VERSION' --generate-notes"
fi
