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
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Embed Sparkle (SPM binary artifact) so the bundle is self-contained.
SPARKLE_SRC="$(find .build -type d -name "Sparkle.framework" -path "*macos*" 2>/dev/null | head -1)"
if [ -n "$SPARKLE_SRC" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$SPARKLE_SRC" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/Granipa" 2>/dev/null || true
fi

# Hardened runtime + entitlements: required for notarization, harmless in dev.
# Sparkle's nested executables must be signed before the framework and the app.
# Secure timestamps need a real certificate, so ad-hoc skips them.
sign_bundle() {
  local id="$1"; shift
  local fw="$APP/Contents/Frameworks/Sparkle.framework"
  if [ -d "$fw" ]; then
    find "$fw" \( -name "*.xpc" -o -name "Autoupdate" -o -name "Updater.app" \) -print0 \
      | while IFS= read -r -d '' item; do
        codesign --force --options runtime "$@" --sign "$id" "$item"
      done
    codesign --force --options runtime "$@" --sign "$id" "$fw"
  fi
  codesign --force --options runtime --entitlements Resources/Granipa.entitlements \
    "$@" --sign "$id" "$APP"
}

if [ "$SIGN_ID" = "-" ]; then
  sign_bundle -
elif ! sign_bundle "$SIGN_ID" --timestamp 2>/dev/null; then
  echo "WARN: signing with '$SIGN_ID' failed (locked keychain?); using ad-hoc signature."
  echo "      Ad-hoc builds re-prompt for audio permissions after every rebuild."
  sign_bundle -
fi

echo "Built $APP"
