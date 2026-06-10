#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
# Ad-hoc signing ("-") changes the CDHash every build, which resets the
# system-audio TCC grant. Default to the first real identity if one exists.
SIGN_ID="${CODESIGN_ID:-$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')}"
SIGN_ID="${SIGN_ID:--}"

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Granipa"

APP="build/Grañipa.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Granipa"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if ! codesign --force --sign "$SIGN_ID" "$APP" 2>/dev/null; then
  echo "WARN: signing with '$SIGN_ID' failed (locked keychain?); using ad-hoc signature."
  echo "      Ad-hoc builds re-prompt for audio permissions after every rebuild."
  codesign --force --sign - "$APP"
fi

echo "Built $APP"
