#!/bin/bash
# Launches Grañipa against an isolated throwaway home so V2 fixture
# screenshots and scroll profiles never touch the production database.
# Debug bundles only: the --v2-fixture seam is compiled out of release
# builds. CFFIXED_USER_HOME isolates FileManager Application Support
# (database and fixture audio); it does not redirect UserDefaults.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Grañipa.app"
BIN="$APP/Contents/MacOS/Granipa"

usage() {
  cat <<'EOF'
Usage: Scripts/v2-fixture.sh [--build] <shell|many>

Runs the existing signed debug bundle with --v2-fixture under a fresh
CFFIXED_USER_HOME created in /private/tmp. The fixture dataset (database
and placeholder audio) lives inside that temp home, which is deleted when
the app exits. Fixture startup does not write persisted UserDefaults.
Opening Settings or otherwise mutating preferences is not sandboxed.

  shell     small deterministic dataset: folders, meetings, transcript,
            notes, and recordings (tiny placeholder files)
  many      exactly 200 meetings for LazyVStack scroll profiling

Options:
  --build   rebuild the debug bundle first (Scripts/bundle.sh)
  -h, --help  show this help
EOF
}

BUILD=0
FIXTURE=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    --build) BUILD=1 ;;
    shell|many) FIXTURE="$arg" ;;
    *)
      echo "ERROR: unknown argument '$arg'." >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [ -z "$FIXTURE" ]; then
  echo "ERROR: fixture name required (shell or many)." >&2
  usage >&2
  exit 2
fi

if [ "$BUILD" -eq 1 ]; then
  ./Scripts/bundle.sh
fi

if [ ! -x "$BIN" ]; then
  echo "ERROR: $APP is missing or not runnable." >&2
  echo "       Build it with ./Scripts/bundle.sh, or pass --build." >&2
  exit 1
fi

if ! strings "$BIN" | grep -F -- '--v2-fixture' >/dev/null; then
  echo "ERROR: $APP has no Debug --v2-fixture seam. Rebuild debug (./Scripts/bundle.sh / --build)." >&2
  exit 1
fi

ROOT="$(mktemp -d /private/tmp/granipa-v2-fixture.XXXXXX)"
cleanup() {
  # Delete only the exact directory this run created, and only if it still
  # matches the mktemp pattern.
  case "$ROOT" in
    /private/tmp/granipa-v2-fixture.*) rm -rf -- "$ROOT" ;;
  esac
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

echo "Fixture '$FIXTURE' home (deleted on exit): $ROOT"
CFFIXED_USER_HOME="$ROOT" "$BIN" --v2-fixture "$FIXTURE"
