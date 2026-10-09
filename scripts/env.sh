# Shared env for scripts. Sourced, not executed.
# xcode-select may point at CommandLineTools, which has no xcodebuild/simctl.
if [ -z "${DEVELOPER_DIR:-}" ] && ! xcodebuild -version >/dev/null 2>&1; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED="$ROOT/build"
# Debug builds use a separate bundle ID (and so separate data) from Release.
BUNDLE_ID="io.github.djam90.notez.dev"
RELEASE_BUNDLE_ID="io.github.djam90.notez"
