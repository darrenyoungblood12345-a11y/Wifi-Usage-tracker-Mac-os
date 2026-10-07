# Shared paths for the build scripts (sourced, not executed).
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/app"
DIST="$ROOT/dist"
# Build outside the project folder: when it lives in an iCloud-synced Desktop/Documents, sync adds
# Finder/File Provider xattrs to bundles, which codesign rejects and which break signatures after the fact.
BUILD_ROOT="${BUILD_ROOT:-$HOME/Library/Caches/WiFiTracker-build}"
SCRATCH="$BUILD_ROOT/swiftpm"
APP="$BUILD_ROOT/WiFi Tracker.app"
DMG="$DIST/WiFiTracker.dmg"
