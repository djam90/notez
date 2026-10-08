#!/usr/bin/env bash
# One-time setup for a fresh clone or git worktree.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT/editor"
npm ci
echo "Ready. Xcode builds use the committed Notez/Resources/editor.html; run scripts/build.sh editor after editing editor/src."
