#!/usr/bin/env bash
# Build, install and launch on a simulator, streaming the app console
# (JS errors show as "[editor] ..."). Usage: SIM_NAME="iPad Pro 11-inch (M5)" scripts/run-sim.sh
# Add --screenshot to save /tmp/notez-sim.png after launch instead of streaming.
set -euo pipefail
source "$(dirname "$0")/env.sh"
sim="${SIM_NAME:-iPhone 18 Pro}"
SIM_NAME="$sim" "$ROOT/scripts/build.sh" ios
udid=$(xcrun simctl list devices available | grep -F "$sim (" | head -1 | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$udid" 2>/dev/null || true
xcrun simctl bootstatus "$udid" -b >/dev/null
xcrun simctl install "$udid" "$DERIVED/Build/Products/Debug-iphonesimulator/Notez.app"
if [ "${1:-}" = "--screenshot" ]; then
  xcrun simctl launch --terminate-running-process "$udid" "$BUNDLE_ID" >/dev/null
  sleep 4
  xcrun simctl io "$udid" screenshot /tmp/notez-sim.png >/dev/null
  echo /tmp/notez-sim.png
else
  xcrun simctl launch --console-pty --terminate-running-process "$udid" "$BUNDLE_ID"
fi
