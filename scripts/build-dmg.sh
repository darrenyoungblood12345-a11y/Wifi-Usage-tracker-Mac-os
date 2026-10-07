#!/usr/bin/env bash
# Builds the app and packages it as dist/WiFiTracker.dmg (drag-to-Applications layout).
# Also copies the DMG into landing/downloads/ so the local landing page preview can serve it.
set -euo pipefail

source "$(dirname "$0")/env.sh"

"$ROOT/scripts/build-app.sh"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
ditto --norsrc --noextattr --noqtn "$APP" "$STAGING/WiFi Tracker.app"
codesign --verify --strict "$STAGING/WiFi Tracker.app"
ln -s /Applications "$STAGING/Applications"

echo "→ Creating $DMG"
mkdir -p "$DIST"
rm -f "$DMG"
hdiutil create -volname "WiFi Tracker" -srcfolder "$STAGING" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$DMG" >/dev/null
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
hdiutil verify "$DMG" >/dev/null

mkdir -p "$ROOT/landing/downloads"
cp "$DMG" "$ROOT/landing/downloads/WiFiTracker.dmg"
echo "✓ $DMG ($(du -h "$DMG" | cut -f1 | xargs))"
