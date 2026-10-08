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
- [x] (confirmed by user) push, enable Pages, release v1.0.0

## Review

- 18 core tests pass (`scripts/test.sh`).
- Accounting verified against the kernel: DB delta == the app's counter delta byte-for-byte; vs `netstat -ib`
  within 0.01% down / 0.5% up (background traffic in the quit/read gap), including catch-up while closed.
- Universal binary (arm64 + x86_64), minos 14.0, ad-hoc signed; signature valid inside the DMG (1.0 MB).
- Idle cost: ~20 MB footprint, ~3% of one core — almost all AppKit redrawing the status item each second.
- Landing page checked at 1440px and 375px, light and dark; no horizontal overflow; local download serves the DMG.
- Not yet verified: Location prompt → SSID names (needs a user click), launch-at-login from /Applications.
- Published 2026-10-07: release v1.0.0 (DMG downloaded from releases/latest is byte-identical to the local build);
  site live at https://darrenyoungblood12345-a11y.github.io/Wifi-Usage-tracker-Mac-os/ (first deploy failed on an
  artifact race; fixed by splitting build/deploy jobs).

---

# Per-app Wi-Fi usage on the dashboard (2026-10-07)

Plan: sample `nettop -L 1 … -t wifi` every 2 s (a long-running nettop costs ~130% CPU), diff per socket, group
into apps (outermost `.app`; XPC services via responsible pid), store hourly in `app_usage`, show an Apps card
sorted by total with live speeds. Wi-Fi bytes not attributed to an app are stored as "Other traffic".

- [x] Core: nettop parser, SocketDeltaTracker, app bundle path helper, AppUsage types/merge/unattributed
- [x] Core: UsageStore `app_usage` table, addAppUsage, appUsage(in:), deleteAll, transaction helper
- [x] Core tests
- [x] App: Nettop runner, AppTrafficSampler (resolver), AppTrafficMonitor; wire into TrafficMonitor flush/clear
- [x] Views: UsageBar extraction, AppsSection card, dashboard placement, snapshot height
- [x] Seed demo data, README, landing copy, screenshots
- [x] Verify: tests, curl reference download, sum(apps)+Other == usage, CPU overhead, layout at 780 pt

## Review

- 33 core tests pass (15 new: nettop parsing, per-socket deltas, app bundles, app list/Other, store + migration).
- Reference check: a 50,000,000-byte rate-limited `curl` download was recorded as 50,099,338 B for `curl`
  (+0.2%, TLS/HTTP framing). Live row showed ↓ 3.16 MB/s for a `--limit-rate 3M` (3.15 MB/s) download.
- Sum check (scratch DB, first flush): apps 50.44 MB ↓ / 0.30 MB ↑ ≤ interface 52.72 MB ↓ / 0.76 MB ↑; the ~4%
  gap is TCP/IP headers (interface counts them, sockets don't) and shows as "Other traffic".
- Grouping verified live: Chrome, Claude and VS Code helpers each collapse into one row with the app icon;
  daemons (mDNSResponder, cloudd, nsurlsessiond) appear by executable name.
- Overhead: app 1.8% CPU over 60 s plus ~0.5% for 30 nettop snapshots/min; phys_footprint 20 MB (unchanged).
- Layout: demo snapshots (light/dark) at 980×1600; min window width 780 leaves the bar ~180 pt (same columns as
  Networks, by arithmetic, not rendered). Landing page checked at 1280 and 375 px: no horizontal overflow.
- Incident: one measurement run launched the test bundle without `WIFITRACKER_STORE` (exported after `&`), so
  it caught up against the real database and double-counted ~43 MB ↓ in the 2026-10-07 17:00 minute bucket.
  Reported to the user; not corrected without their go-ahead.
- Not done: 5-minute comparison against a long-running `nettop -P -d` (the curl byte count is an independent
  reference instead); CSV export still covers networks only.
