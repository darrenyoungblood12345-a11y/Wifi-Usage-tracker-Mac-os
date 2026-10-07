#!/usr/bin/env bash
# Builds a universal (Apple Silicon + Intel) release of WiFi Tracker into $BUILD_ROOT/WiFi Tracker.app.
#
# Signing: ad-hoc by default. Set SIGN_IDENTITY="Developer ID Application: …" to sign for distribution
# with the hardened runtime (notarize the resulting DMG separately).
set -euo pipefail

source "$(dirname "$0")/env.sh"
PLIST="$PACKAGE/Resources/Info.plist"
VERSION="${VERSION:-$(plutil -extract CFBundleShortVersionString raw "$PLIST")}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"

echo "→ Building WiFi Tracker $VERSION ($BUILD_NUMBER), universal release"
SWIFT_BUILD=(swift build --package-path "$PACKAGE" --scratch-path "$SCRATCH" -c release --arch arm64 --arch x86_64)
"${SWIFT_BUILD[@]}"
BIN_DIR="$("${SWIFT_BUILD[@]}" --show-bin-path)"

[[ -f "$PACKAGE/Resources/AppIcon.icns" ]] || "$ROOT/scripts/make-icon.sh"

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/WiFiTracker" "$APP/Contents/MacOS/WiFiTracker"
cp "$PACKAGE/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp "$PLIST" "$APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

ENTITLEMENTS="$PACKAGE/Resources/WiFiTracker.entitlements"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "→ Signing with $SIGN_IDENTITY (hardened runtime)"
  codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$SIGN_IDENTITY" "$APP"
else
  echo "→ Ad-hoc signing (no Developer ID configured)"
  codesign --force --entitlements "$ENTITLEMENTS" --sign - "$APP"
fi
codesign --verify --strict "$APP"

echo "✓ $(lipo -archs "$APP/Contents/MacOS/WiFiTracker") → $APP"
