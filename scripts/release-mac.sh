#!/usr/bin/env bash
# Release a new version of the Mac app for everyday use:
# bump the version, build Release, back up your data, install to
# /Applications/Notez.app, commit and tag. Dev builds (scripts/run-mac.sh) are a
# separate app ("Notez Dev") with separate data, so they never touch this one.
# Usage: scripts/release-mac.sh 0.2.0
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"

version="${1:-}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: scripts/release-mac.sh <x.y.z>" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Working tree not clean, commit first." >&2; exit 1; }
! git rev-parse -q --verify "refs/tags/v$version" >/dev/null || { echo "Tag v$version already exists." >&2; exit 1; }

pbx="Notez.xcodeproj/project.pbxproj"
build=$(( $(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+' "$pbx" | grep -oE '[0-9]+$') + 1 ))
trap 'git checkout -- "$pbx"' ERR
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $build;/" "$pbx"

echo "Building v$version ($build)..."
xcodebuild -project Notez.xcodeproj -scheme Notez -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- build 2>&1 | grep -E "error:|BUILD"
app="$DERIVED/Build/Products/Release/Notez.app"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = "$RELEASE_BUNDLE_ID" ]

# Quit the installed copy only. `is running` guards against AppleScript launching it.
osascript -e "if application id \"$RELEASE_BUNDLE_ID\" is running then tell application id \"$RELEASE_BUNDLE_ID\" to quit" || true
while pgrep -f "/Applications/Notez.app/Contents/MacOS/Notez" >/dev/null; do sleep 0.2; done

# The app also backs itself up on a version change, but that copy lives inside
# the container. This one survives deleting the app.
data="$HOME/Library/Containers/$RELEASE_BUNDLE_ID/Data/Library/Application Support"
if [ -f "$data/default.store" ]; then
  backup="$HOME/Notez-backups/$(date +%Y-%m-%d-%H%M%S)-before-v$version"
  mkdir -p "$backup"
  for f in default.store default.store-wal default.store-shm .default_SUPPORT; do
    [ -e "$data/$f" ] && cp -R "$data/$f" "$backup/"
  done
  echo "Backed up data to $backup"
fi

rm -rf /Applications/Notez.app
ditto "$app" /Applications/Notez.app

git commit -q -m "Release v$version" -- "$pbx"
git tag "v$version"
trap - ERR
open /Applications/Notez.app
echo "Installed Notez v$version ($build), tagged v$version on $(git branch --show-current)."
