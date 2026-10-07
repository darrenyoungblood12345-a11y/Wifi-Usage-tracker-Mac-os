#!/usr/bin/env bash
# Renders the app icon and packs it into app/Resources/AppIcon.icns (plus a PNG for the website).
set -euo pipefail

source "$(dirname "$0")/env.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift "$ROOT/scripts/make-icon.swift" "$WORK/icon-1024.png"

ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" "$WORK/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$ROOT/app/Resources/AppIcon.icns"

mkdir -p "$ROOT/landing/assets"
sips -z 512 512 "$WORK/icon-1024.png" --out "$ROOT/landing/assets/icon.png" >/dev/null
echo "Icon written to app/Resources/AppIcon.icns and landing/assets/icon.png"
