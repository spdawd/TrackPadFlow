#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$APP_ROOT/build/TrackpadFlow.app"
DIST_ROOT="$APP_ROOT/dist"

if [[ "${1:-}" != "--skip-build" ]]; then
  "$SCRIPT_DIR/build_app.sh"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
  echo "Missing build product: $APP_BUNDLE" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")"
ARCHIVE_NAME="TrackpadFlow-v${VERSION}-macOS.zip"
ARCHIVE_PATH="$DIST_ROOT/$ARCHIVE_NAME"
CHECKSUM_PATH="$ARCHIVE_PATH.sha256"

mkdir -p "$DIST_ROOT"
rm -f "$ARCHIVE_PATH" "$CHECKSUM_PATH"

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"

# Info-ZIP does not emit AppleDouble `._*` entries for extended attributes.
# Those metadata files are harmless on macOS, but make public release archives
# look noisy when inspected or extracted on other platforms.
cd "$APP_ROOT/build"
/usr/bin/zip -qry -y "$ARCHIVE_PATH" "TrackpadFlow.app"

cd "$DIST_ROOT"
/usr/bin/shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"

echo "Created: $ARCHIVE_PATH"
echo "Checksum: $CHECKSUM_PATH"
