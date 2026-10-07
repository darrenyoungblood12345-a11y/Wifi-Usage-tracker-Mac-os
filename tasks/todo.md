# WiFi Tracker — todo

Plan: native SwiftUI menu bar + dashboard app, per-SSID usage, .dmg, landing page on GitHub Pages.

- [x] Scaffold Swift package, Info.plist, .gitignore
- [x] Core: InterfaceCounters (IFMIB sysctl, 64-bit; IFLIST2 was truncated), TrafficDelta, Aggregation, UsageStore (SQLite), Formatters
- [x] Core tests (Swift Testing)
- [x] App: TrafficMonitor, WiFiInfo, LoginItem, scenes
- [x] Views: menu bar label/popover, dashboard, charts, networks, settings
- [x] Icon script, build-app.sh, build-dmg.sh
- [x] Build, launch, verify counters vs netstat
- [x] Landing page + Pages workflow + screenshot
- [x] git init, initial commit
- [ ] (confirm) push, enable Pages, release v1.0.0

## Review

- 18 core tests pass (`scripts/test.sh`).
- Accounting verified against the kernel: DB delta == the app's counter delta byte-for-byte; vs `netstat -ib`
  within 0.01% down / 0.5% up (background traffic in the quit/read gap), including catch-up while closed.
- Universal binary (arm64 + x86_64), minos 14.0, ad-hoc signed; signature valid inside the DMG (1.0 MB).
- Idle cost: ~20 MB footprint, ~3% of one core — almost all AppKit redrawing the status item each second.
- Landing page checked at 1440px and 375px, light and dark; no horizontal overflow; local download serves the DMG.
- Not yet verified: Location prompt → SSID names (needs a user click), launch-at-login from /Applications.
