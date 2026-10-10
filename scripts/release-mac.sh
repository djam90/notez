#!/usr/bin/env bash
# Ship the current worktree's branch: rebase onto origin/main, build-check iOS,
# bump the version, build Release, push to main with a tag, back up your data
# and install /Applications/Notez.app. Run it from the feature's worktree.
# Dev builds (scripts/run-mac.sh) are a separate app ("Notez Dev") with
# separate data, so they never touch the installed one.
# Usage: scripts/release-mac.sh [patch|minor|major|x.y.z]   (default: patch)
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"

die() { echo "error: $*" >&2; exit 1; }

[ -z "$(git status --porcelain)" ] || die "working tree not clean, commit first."

echo "Fetching origin..."
git fetch -q --tags origin
if ! git rebase -q origin/main; then
  git rebase --abort
  die "your branch conflicts with origin/main. Run 'git rebase origin/main', resolve, then release again."
fi

# Next version from the newest tag (they're all on main once pushed).
last=$(git tag --list 'v*' --sort=-v:refname | head -1)
IFS=. read -r major minor patch <<<"${last#v}"
case "${1:-patch}" in
  patch) version="$major.$minor.$((patch + 1))" ;;
  minor) version="$major.$((minor + 1)).0" ;;
  major) version="$((major + 1)).0.0" ;;
  *) version="$1" ;;
esac
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: scripts/release-mac.sh [patch|minor|major|x.y.z]"
! git rev-parse -q --verify "refs/tags/v$version" >/dev/null || die "tag v$version already exists."
echo "Releasing v$version (last was ${last:-none}) from $(git branch --show-current)"

# Platform #if branches can break iOS without touching the Mac build.
echo "Checking the iOS build..."
"$ROOT/scripts/build.sh" ios >/dev/null || die "iOS build failed, run scripts/build.sh ios to see why."

pbx="Notez.xcodeproj/project.pbxproj"
build=$(( $(grep -m1 -oE 'CURRENT_PROJECT_VERSION = [0-9]+' "$pbx" | grep -oE '[0-9]+$') + 1 ))
trap 'git checkout -- "$pbx"' ERR
sed -i '' -E "s/MARKETING_VERSION = [^;]+;/MARKETING_VERSION = $version;/; s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $build;/" "$pbx"

echo "Building Release v$version ($build)..."
xcodebuild -project Notez.xcodeproj -scheme Notez -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" CODE_SIGN_IDENTITY=- build 2>&1 | grep -E "error:|BUILD"
app="$DERIVED/Build/Products/Release/Notez.app"
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")" = "$RELEASE_BUNDLE_ID" ]

git commit -q -m "Release v$version" -- "$pbx"
git tag "v$version"
# Push before installing, so a rejected push (someone released in the
# meantime) leaves nothing half-done. --atomic: main and the tag land together.
trap - ERR
if ! git push -q --atomic origin HEAD:main "refs/tags/v$version"; then
  git tag -d "v$version" >/dev/null
  git reset -q --hard HEAD~1
  die "push failed (main moved while building?). Release again to rebase onto it."
fi

# Quit the installed copy only. `is running` guards against AppleScript launching it.
osascript -e "if application id \"$RELEASE_BUNDLE_ID\" is running then tell application id \"$RELEASE_BUNDLE_ID\" to quit" || true
while pgrep -f "/Applications/Notez.app/Contents/MacOS/Notez" >/dev/null; do sleep 0.2; done

# The app also backs itself up on a version change, but that copy lives inside
# the container. This one survives deleting the app. Keeps the newest 10.
data="$HOME/Library/Containers/$RELEASE_BUNDLE_ID/Data/Library/Application Support"
backups="$HOME/Notez-backups"
if [ -f "$data/default.store" ]; then
  backup="$backups/$(date +%Y-%m-%d-%H%M%S)-before-v$version"
  mkdir -p "$backup"
  for f in default.store default.store-wal default.store-shm .default_SUPPORT; do
    [ -e "$data/$f" ] && cp -R "$data/$f" "$backup/"
  done
  echo "Backed up data to $backup"
  ls -1d "$backups"/*/ | sort -r | tail -n +11 | while read -r old; do rm -rf "$old"; done
fi

# Copy first, then swap, so a failed copy never leaves you without an app.
rm -rf /Applications/.Notez.app.new /Applications/.Notez.app.old
ditto "$app" /Applications/.Notez.app.new
[ -e /Applications/Notez.app ] && mv /Applications/Notez.app /Applications/.Notez.app.old
mv /Applications/.Notez.app.new /Applications/Notez.app
rm -rf /Applications/.Notez.app.old
open /Applications/Notez.app

# A blank window has shipped before. Wait for the app to show one.
window=""
for _ in $(seq 20); do
  sleep 0.5
  pid=$(pgrep -f "/Applications/Notez.app/Contents/MacOS/Notez" | head -1) || continue
  window=$(swift - "$pid" <<'SWIFT'
import CoreGraphics
let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
if list.contains(where: { ($0[kCGWindowOwnerPID as String] as? Int) == pid && ($0[kCGWindowLayer as String] as? Int) == 0 }) {
    print("yes")
}
SWIFT
  ) && [ -n "$window" ] && break
done
[ -n "$window" ] || echo "WARNING: Notez v$version launched but no window appeared. Check it now." >&2

# Keep the main checkout's local main in step when it's safe to.
main_tree=$(git worktree list --porcelain | awk '/^worktree /{p=$2} /^branch refs\/heads\/main$/{print p}')
if [ -n "$main_tree" ] && [ -z "$(git -C "$main_tree" status --porcelain)" ]; then
  git -C "$main_tree" merge -q --ff-only origin/main 2>/dev/null || true
elif [ -z "$main_tree" ]; then
  git branch -f main origin/main
fi

echo "Released Notez v$version ($build): pushed to main, tagged, installed."

# Other in-progress worktrees pick this up when they next release (it rebases),
# but rebasing sooner keeps conflicts small.
current=$(git branch --show-current)
git worktree list --porcelain | awk '/^branch refs\/heads\//{sub("refs/heads/", "", $2); print $2}' |
  while read -r branch; do
    [ "$branch" = "$current" ] || [ "$branch" = main ] && continue
    behind=$(git rev-list --count "$branch..origin/main")
    if [ "$behind" -gt 0 ]; then echo "  $branch is $behind commits behind main (git rebase origin/main)"; fi
  done
