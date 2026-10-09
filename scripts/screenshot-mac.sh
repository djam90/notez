#!/usr/bin/env bash
# Screenshot only the running Notez Dev window (never the whole screen, which
# would capture whatever else the user has open). Saves /tmp/notez-mac.png.
set -euo pipefail
source "$(dirname "$0")/env.sh"
pid=$(pgrep -f "$DERIVED/Build/Products/Debug/Notez.app/Contents/MacOS/Notez" | head -1) || {
  echo "Notez Dev isn't running (scripts/run-mac.sh)" >&2; exit 1; }
id=$(swift - "$pid" <<'SWIFT'
import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
if let w = list.first(where: { ($0[kCGWindowOwnerPID as String] as? Int) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }) {
    print(w[kCGWindowNumber as String]!)
}
SWIFT
)
[ -n "$id" ] || { echo "No on-screen Notez Dev window" >&2; exit 1; }
screencapture -x -o -l"$id" /tmp/notez-mac.png
echo /tmp/notez-mac.png
