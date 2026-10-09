#!/usr/bin/env bash
# Build and (re)launch the macOS Debug app ("Notez Dev", its own data).
set -euo pipefail
source "$(dirname "$0")/env.sh"
"$ROOT/scripts/build.sh" mac
# Match the Debug path so an installed /Applications/Notez.app keeps running.
exe="$DERIVED/Build/Products/Debug/Notez.app/Contents/MacOS/Notez"
pkill -f "$exe" 2>/dev/null || true
while pgrep -f "$exe" >/dev/null; do sleep 0.2; done
open "$DERIVED/Build/Products/Debug/Notez.app"
