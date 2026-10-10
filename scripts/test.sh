#!/usr/bin/env bash
# Usage: scripts/test.sh [unit|ui|editor|all]...   (default: unit editor)
#   unit    Swift Testing suite (NotezTests), hosted in Notez Dev with in-memory data
#   ui      XCUITest smoke tests (NotezUITests). Takes over the keyboard and
#           screen for about a minute, and quits any running Notez Dev.
#   editor  Vitest + Playwright for editor/
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"

xctest() { # $1 = test target, $2 = summary line pattern
  local log="$DERIVED/test-$1.log" bundle="$DERIVED/TestResults/$1.xcresult"
  rm -rf "$bundle"
  echo "Running $1..."
  if xcodebuild test -project Notez.xcodeproj -scheme Notez -destination 'platform=macOS' \
      -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- -only-testing:"$1" \
      -resultBundlePath "$bundle" >"$log" 2>&1; then
    grep -E "$2" "$log" | tail -1
  else
    # Compile errors, Swift Testing issues and XCTest failures, minus system log noise.
    grep -E "\.swift:[0-9]+:[0-9]+: error:|^✘|: error: -\[|Executed [0-9]+ tests?, with [1-9]" "$log" | head -40 || true
    echo "$1 FAILED. Log: $log  Results: open $bundle" >&2
    return 1
  fi
}

editor() {
  [ -d editor/node_modules ] || (cd editor && npm ci)
  echo "Running editor unit tests..."
  (cd editor && npm test --silent)
  echo "Running editor e2e tests..."
  (cd editor && npm run --silent test:e2e -- --reporter=dot)
}

targets=("$@")
[ ${#targets[@]} -gt 0 ] || targets=(unit editor)
for target in "${targets[@]}"; do
  case "$target" in
    unit) xctest NotezTests "^✔ Test run" ;;
    ui) xctest NotezUITests "Executed [0-9]+ tests?, with 0 failures" ;;
    editor) editor ;;
    all) "$0" unit editor ui ;;
    *) echo "unknown target: $target (unit|ui|editor|all)" >&2; exit 1 ;;
  esac
done
