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
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> Stapling ticket and producing final artifact"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "Release artifact: $ZIP"
shasum -a 256 "$ZIP"
echo
echo "Publish with:"
echo "  gh release create v$VERSION '$ZIP' --title 'Grañipa v$VERSION' --generate-notes"
