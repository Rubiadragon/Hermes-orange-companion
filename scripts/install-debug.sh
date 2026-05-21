#!/usr/bin/env zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_SOURCE="$ROOT_DIR/build/DerivedData/Build/Products/Debug/MOrange Companion.app"
APP_DEST="/Applications/小橘子桌宠.app"

"$ROOT_DIR/scripts/build-debug.sh"

pkill -f "MOrange Companion" 2>/dev/null || true
rm -rf "$APP_DEST"
/usr/bin/ditto "$APP_SOURCE" "$APP_DEST"
open -n "$APP_DEST"
