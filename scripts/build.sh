#!/usr/bin/env bash
# Usage: scripts/build.sh [editor|mac|ios|all]   (default: all)
set -euo pipefail
source "$(dirname "$0")/env.sh"
target="${1:-all}"

build_editor() {
  (cd "$ROOT/editor" && npm run build)
}
build_mac() {
  xcodebuild -project "$ROOT/Notez.xcodeproj" -scheme Notez -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- build 2>&1 | grep -E "error:|warning: [^M]|BUILD"
}
build_ios() {
  local sim="${SIM_NAME:-iPhone 18 Pro}"
  xcodebuild -project "$ROOT/Notez.xcodeproj" -scheme Notez -destination "platform=iOS Simulator,name=$sim" \
    -derivedDataPath "$DERIVED" build 2>&1 | grep -E "error:|warning: [^M]|BUILD"
}

case "$target" in
  editor) build_editor ;;
  mac) build_mac ;;
  ios) build_ios ;;
  all) build_editor; build_mac; build_ios ;;
  *) echo "unknown target: $target" >&2; exit 1 ;;
esac
