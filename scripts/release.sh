#!/usr/bin/env bash
# Publishes a GitHub release with the DMG attached. The landing page always links to
# releases/latest/download/WiFiTracker.dmg, so it picks the new version up automatically.
# Usage: scripts/release.sh 1.0.0
set -euo pipefail

VERSION="${1:?Usage: scripts/release.sh <version>}"
source "$(dirname "$0")/env.sh"
REPO="darrenyoungblood12345-a11y/Wifi-Usage-tracker-Mac-os"
PLIST="$PACKAGE/Resources/Info.plist"

if [[ -n "$(git -C "$ROOT" status --porcelain)" ]]; then
  echo "Commit or stash your changes first." >&2
  exit 1
fi

if [[ "$(plutil -extract CFBundleShortVersionString raw "$PLIST")" != "$VERSION" ]]; then
  plutil -replace CFBundleShortVersionString -string "$VERSION" "$PLIST"
  git -C "$ROOT" commit -m "chore: release $VERSION" -- "$PLIST"
fi

# The release tag points at this commit, so it has to be on GitHub first.
git -C "$ROOT" push origin HEAD

"$ROOT/scripts/build-dmg.sh"

gh release create "v$VERSION" "$DMG" \
  --repo "$REPO" \
  --target "$(git -C "$ROOT" rev-parse HEAD)" \
  --title "WiFi Tracker $VERSION" \
  --notes "Download **WiFiTracker.dmg** below, open it and drag WiFi Tracker to Applications. Requires macOS 14 Sonoma or later on Apple silicon or Intel.

The app isn't notarized yet, so macOS blocks the first launch: open **System Settings → Privacy & Security** and click **Open Anyway**.

Landing page: https://darrenyoungblood12345-a11y.github.io/Wifi-Usage-tracker-Mac-os/"
