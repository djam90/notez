#!/usr/bin/env bash
# Snapshot the current models as a SwiftData store for MigrationTests, so every
# later build is tested against data written by this one. Run it after any
# change under Notez/Models and commit the new NotezTests/Fixtures/*.store.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"

out="NotezTests/Fixtures/store-$(date +%Y-%m-%d).store"
[ ! -e "$out" ] || out="NotezTests/Fixtures/store-$(date +%Y-%m-%d-%H%M%S).store"
# The hosted test runs inside the sandboxed dev app, so it writes to its container.
tmp="$HOME/Library/Containers/$BUNDLE_ID/Data/tmp/notez-fixture"
rm -rf "$tmp"
log="$DERIVED/make-store-fixture.log"

TEST_RUNNER_NOTEZ_WRITE_FIXTURE=1 xcodebuild test -project Notez.xcodeproj -scheme Notez -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- -only-testing:'NotezTests/MigrationTests/writeFixture()' >"$log" 2>&1 \
  || { echo "Writing the fixture failed, see $log" >&2; exit 1; }
[ -f "$tmp/fixture.store" ] || { echo "No fixture was written (is the test still enabled by NOTEZ_WRITE_FIXTURE?), see $log" >&2; exit 1; }

# Fold the WAL into the main file so the fixture is one self-contained file.
sqlite3 "$tmp/fixture.store" 'PRAGMA wal_checkpoint(TRUNCATE); PRAGMA journal_mode=DELETE;' >/dev/null
mkdir -p "$(dirname "$out")"
cp "$tmp/fixture.store" "$out"
rm -rf "$tmp"
echo "Wrote $out. Commit it with your model change."
