#!/bin/bash
# Builds a distributable zip of Grañipa.app.
#
# For public distribution without Gatekeeper warnings you need a paid Apple
# Developer account and a "Developer ID Application" certificate, then:
#   CODESIGN_ID="Developer ID Application: Your Name (TEAMID)" ./Scripts/release.sh
#   xcrun notarytool submit "build/Granipa-vX.Y.Z.zip" --keychain-profile granipa --wait
#   xcrun stapler staple "build/Grañipa.app"   # then re-zip
# Without that, users must right-click > Open on first launch (or build from source).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(plutil -extract CFBundleShortVersionString raw Resources/Info.plist)
./Scripts/bundle.sh release

ZIP="build/Granipa-v$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "build/Grañipa.app" "$ZIP"

echo
echo "Release artifact: $ZIP"
shasum -a 256 "$ZIP"
