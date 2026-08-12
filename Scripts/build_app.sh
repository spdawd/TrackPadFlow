#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_ROOT="$APP_ROOT/build"
APP_BUNDLE="$BUILD_ROOT/TrackpadFlow.app"

if [[ -n "${TRACKPADFLOW_ENV_ROOT:-}" ]]; then
  SHARED_ENV_ROOT="$TRACKPADFLOW_ENV_ROOT"
elif [[ "$APP_ROOT" == */apps/TrackpadFlow ]]; then
  WORKSPACE_ROOT="$(cd "$APP_ROOT/../.." && pwd)"
  SHARED_ENV_ROOT="$WORKSPACE_ROOT/environment"
else
  USER_CACHE_ROOT="$(getconf DARWIN_USER_CACHE_DIR 2>/dev/null || true)"
  if [[ -z "$USER_CACHE_ROOT" ]]; then
    USER_CACHE_ROOT="${TMPDIR:-/tmp}"
  fi
  SHARED_ENV_ROOT="${USER_CACHE_ROOT%/}/TrackpadFlowBuild"
fi

SWIFT_SCRATCH_ROOT="$SHARED_ENV_ROOT/TrackpadFlow/.build"
SIGN_IDENTITY="${TRACKPADFLOW_SIGN_IDENTITY:--}"

mkdir -p "$BUILD_ROOT"
mkdir -p "$SWIFT_SCRATCH_ROOT"

echo "Using shared environment: $SHARED_ENV_ROOT"
echo "Building TrackpadFlow from: $APP_ROOT"
echo "Using external Swift build cache: $SWIFT_SCRATCH_ROOT"

/usr/bin/swift build \
  --package-path "$APP_ROOT" \
  --scratch-path "$SWIFT_SCRATCH_ROOT" \
  --configuration release

BIN_PATH="$(/usr/bin/swift build \
  --package-path "$APP_ROOT" \
  --scratch-path "$SWIFT_SCRATCH_ROOT" \
  --configuration release \
  --show-bin-path)"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_PATH/TrackpadFlow" "$APP_BUNDLE/Contents/MacOS/TrackpadFlow"
cp "$APP_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$APP_ROOT/Resources/TrackpadFlow.icns" "$APP_BUNDLE/Contents/Resources/TrackpadFlow.icns"
cp "$APP_ROOT/Resources/TrackpadFlow-logo.png" "$APP_BUNDLE/Contents/Resources/TrackpadFlow-logo.png"

chmod +x "$APP_BUNDLE/Contents/MacOS/TrackpadFlow"
/usr/bin/xattr -cr "$APP_BUNDLE"

SIGN_ARGUMENTS=(
  --force
  --deep
  --sign "$SIGN_IDENTITY"
  --identifier "com.jingxuanpan.trackpadflow.menubar"
)

if [[ "$SIGN_IDENTITY" != "-" ]]; then
  SIGN_ARGUMENTS+=(--options runtime --timestamp)
fi

# The default ad-hoc signature is suitable for local development. Public
# release builds should set TRACKPADFLOW_SIGN_IDENTITY to a stable Developer
# ID Application identity before building and notarizing the archive.
/usr/bin/codesign "${SIGN_ARGUMENTS[@]}" "$APP_BUNDLE" >/dev/null

echo "Built: $APP_BUNDLE"
echo "Code signing identity: $SIGN_IDENTITY"
