#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$APP_ROOT/build/TrackpadFlow.app"
INFO_PLIST="$APP_BUNDLE/Contents/Info.plist"
EXPECTED_IDENTIFIER="com.jingxuanpan.trackpadflow.menubar"

echo "Swift toolchain:"
/usr/bin/swift --version

echo "Describing package..."
/usr/bin/swift package --package-path "$APP_ROOT" describe >/dev/null

echo "Building app bundle..."
"$SCRIPT_DIR/build_app.sh"

echo "Checking bundle metadata..."
/usr/bin/plutil -lint "$INFO_PLIST"
ACTUAL_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST")"
if [[ "$ACTUAL_IDENTIFIER" != "$EXPECTED_IDENTIFIER" ]]; then
  echo "Unexpected Bundle Identifier: $ACTUAL_IDENTIFIER" >&2
  exit 1
fi

echo "Checking executable and signature..."
test -x "$APP_BUNDLE/Contents/MacOS/TrackpadFlow"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
/usr/bin/file "$APP_BUNDLE/Contents/MacOS/TrackpadFlow"

if [[ -e "$APP_ROOT/.build" ]]; then
  echo "Project-local .build detected; use the external scratch path instead." >&2
  exit 1
fi

echo "Verification passed."
