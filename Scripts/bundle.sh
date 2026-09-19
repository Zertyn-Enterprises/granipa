#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
TEAM="R4V252C833"

# Signing policy, both configs: a "Developer ID Application" certificate of
# team R4V252C833. Ad-hoc signing resets the system-audio TCC grant every
# rebuild, and no other identity can notarize. CODESIGN_ID (exact name or
# hash) must resolve to such a certificate in the keychain; any other or
# missing identity is a hard error BEFORE building or deleting the previous
# bundle, and signing itself never falls back to ad-hoc.
resolve_sign_id() {
  # `security find-identity` lines look like: '  1) HASH "NAME"'.
  local listing
  listing="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  printf '%s\n' "$listing" | awk -F'"' -v want="${CODESIGN_ID:-}" -v team="($TEAM)" '
    $2 ~ /^Developer ID Application: / &&
    substr($2, length($2) - length(team) + 1) == team {
      hash = $1
      sub(/^.*\) /, "", hash)
      sub(/[ \t]+$/, "", hash)
      if (want == "" || $2 == want || hash == want) {
        print (want == "" ? $2 : want)
        exit
      }
    }'
}

SIGN_ID="$(resolve_sign_id)"
if [ -z "$SIGN_ID" ]; then
  if [ -n "${CODESIGN_ID:-}" ]; then
    echo "ERROR: CODESIGN_ID '$CODESIGN_ID' is not a 'Developer ID Application' certificate of team $TEAM." >&2
  else
    echo "ERROR: no 'Developer ID Application' certificate of team $TEAM in the keychain." >&2
  fi
  exit 1
fi
echo "Signing with: $SIGN_ID"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/Granipa"
HELPER="$BIN_DIR/GranipaBatteryHelper"

APP="build/Grañipa.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN" "$APP/Contents/MacOS/Granipa"
cp "$HELPER" "$APP/Contents/MacOS/GranipaBatteryHelper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/com.zertyn.granipa.batteryhelper.plist \
  "$APP/Contents/Library/LaunchDaemons/com.zertyn.granipa.batteryhelper.plist"

# Embed Sparkle (SPM binary artifact) so the bundle is self-contained.
SPARKLE_SRC="$(find .build -type d -name "Sparkle.framework" -path "*macos*" 2>/dev/null | head -1)"
if [ -n "$SPARKLE_SRC" ]; then
  mkdir -p "$APP/Contents/Frameworks"
  cp -R "$SPARKLE_SRC" "$APP/Contents/Frameworks/"
  install_name_tool -add_rpath "@executable_path/../Frameworks" \
    "$APP/Contents/MacOS/Granipa" 2>/dev/null || true
fi

# Hardened runtime + entitlements are required for notarization. Sparkle's
# nested executables must be signed before the framework and the app; the
# first codesign failure aborts the build.
sign_bundle() {
  local id="$1"; shift
  local options=(--force --options runtime)
  local fw="$APP/Contents/Frameworks/Sparkle.framework"
  if [ -d "$fw" ]; then
    find "$fw" \( -name "*.xpc" -o -name "Autoupdate" -o -name "Updater.app" \) -print0 \
      | while IFS= read -r -d '' item; do
        codesign "${options[@]}" "$@" --sign "$id" "$item" || exit 1
      done
    codesign "${options[@]}" "$@" --sign "$id" "$fw"
  fi
  codesign "${options[@]}" --identifier com.zertyn.granipa.batteryhelper \
    "$@" --sign "$id" \
    "$APP/Contents/MacOS/GranipaBatteryHelper"
  codesign "${options[@]}" --entitlements Resources/Granipa.entitlements \
    "$@" --sign "$id" "$APP"
}

sign_bundle "$SIGN_ID" --timestamp

codesign --verify --deep --strict "$APP"
echo "Built $APP"
