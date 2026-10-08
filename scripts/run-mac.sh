#!/usr/bin/env bash
# Build and (re)launch the macOS app.
set -euo pipefail
source "$(dirname "$0")/env.sh"
"$ROOT/scripts/build.sh" mac
pkill -x Notez 2>/dev/null || true
open "$DERIVED/Build/Products/Debug/Notez.app"
