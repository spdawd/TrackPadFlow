#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SOURCE_APP="$APP_ROOT/build/TrackpadFlow.app"
TARGET_APP="/Applications/TrackpadFlow.app"

if [[ "${1:-}" != "--skip-build" ]]; then
  "$SCRIPT_DIR/build_app.sh"
fi

if [[ ! -d "$SOURCE_APP" ]]; then
  echo "Missing build product: $SOURCE_APP" >&2
  exit 1
fi

/usr/bin/codesign --verify --deep --strict "$SOURCE_APP"
/usr/bin/pkill -x TrackpadFlow 2>/dev/null || true
/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"
/usr/bin/codesign --verify --deep --strict "$TARGET_APP"
/usr/bin/open -n "$TARGET_APP"

echo "Installed: $TARGET_APP"
echo "If the code-signing identity changed, macOS may ask you to confirm permissions again."
