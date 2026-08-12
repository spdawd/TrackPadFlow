#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

"$APP_ROOT/Scripts/build_app.sh"
open -n "$APP_ROOT/build/TrackpadFlow.app"
