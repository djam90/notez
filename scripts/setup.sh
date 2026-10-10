#!/usr/bin/env bash
# One-time setup for a fresh clone or git worktree.
set -euo pipefail
source "$(dirname "$0")/env.sh"
# Shared by all worktrees. Blocks code commits that leave the docs behind.
git -C "$ROOT" config core.hooksPath scripts/githooks
cd "$ROOT/editor"
npm ci
# Browsers for the editor's Playwright tests. Cached per machine, so later worktrees skip the download.
npx playwright install webkit chromium
echo "Ready. Xcode builds use the committed Notez/Resources/editor.html; run scripts/build.sh editor after editing editor/src."
