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

---

# Per-network tracking and delayed updates (2026-10-08)

Request: investigate missing/incorrect per-network usage and make a plan before implementation.
The user clarified that a network eventually appeared after about 15 minutes.

## Investigation and evidence

- [x] Review project lessons, sampling, network discovery, persistence, checkpoint recovery, and dashboard reloads.
- [x] Independently review attribution and delayed-update paths with a read-only subagent.
- [x] Inspect the existing database read-only, without exposing SSIDs or launching another tracking instance.
- [x] Run the existing test suite: all 33 Swift Testing tests pass.
- [x] Write the implementation and verification plan for review; user approved implementation on 2026-10-08.

Observed on this Mac (times are America/Los_Angeles):

- SQLite `quick_check` returns `ok`. History contains three named networks plus the generic `Wi-Fi` label.
- After wake at 10:18:42, minute buckets from 10:18 through 10:28 contain generic `Wi-Fi` usage. At 10:29,
  both generic and named usage appear; subsequent minutes use the named network. The generic bytes in
  10:18–10:29 total 943,295,418 B (862,421,638 downloaded; 80,873,780 uploaded).
- This is evidence that counting continued while network-name attribution was unavailable. It does not
  establish why the name was unavailable or prove that all generic bytes belong to the subsequently named network.
- Earlier 11–18-minute gaps coincide with system sleep/dark-wake intervals. Those gaps do not prove an
  awake-state scheduling failure. The user's exact 15-minute dashboard delay has not been reproduced.
- One installed tracker process was running from `/Applications/WiFi Tracker.app`. No application code,
  installed app, live history, or network settings were changed during this investigation.

Confirmed code issues:

1. `WiFiInfo.swift:40,57,78`: an unavailable SSID becomes `Wi-Fi`; names refresh every five seconds.
   `canReadNetworkNames` checks authorization alone, so it can report access even when names are unavailable.
   Apple's installed CoreWLAN SDK documents that both enabled Location Services and app authorization are required;
   `ssid()` can also return nil on errors or disconnection. The database cannot distinguish these causes.
2. `DashboardView.swift:19,74` and `TrafficMonitor.swift:143,145`: Networks/history query only saved records,
   whereas live totals include pending traffic. Normal visible lag can therefore approach 60 seconds.
3. `TrafficMonitor.swift:126,135,145`: early returns, including failed counter reads, skip the due-flush check.
   Buffered records can stay hidden until successful comparable samples resume. There is no wake/activation refresh.
4. `TrafficMonitor.swift:91,94,97`: history invalidation happens only after network writes, app writes, and
   totals reads all succeed. A later failure can leave the UI stale despite committed network records.
   `storeError` is never displayed, and history read errors are silently replaced with empty results.
5. `TrafficMonitor.swift:135,143`: deltas validate interface identity but never previous network identity.
   A switch on the same interface can assign new traffic to a stale name or mix two networks in one delta.
6. `TrafficMonitor.swift:206,219`: restart recovery assigns all traffic while closed to the saved network.
   Matching SSIDs at the endpoints cannot establish continuous use of that network during the gap.
7. `TrafficMonitor.swift:130,146,194`: automatic flush commits this tick's usage before the deferred counter
   update; its checkpoint is one sample behind. Forced exit/restart can duplicate that sample. Usage and
   the UserDefaults checkpoint also have a separate-write crash window.

## Proposed implementation order

- [x] **1. Establish the cause of unavailable network names.** Add small local diagnostics for the actual
  bundled app: sample time, interface/connection state, global Location Services state, app authorization,
  SSID availability, successful flush time, and history reload time. Keep raw SSIDs out of logs. Reproduce
  wake, connection changes, permission changes, dashboard reopening, and an awake/background interval.
  Distinguish name-read failures from timer stalls, buffered data, and UI reload failures before changing scheduling.
- [x] **2. Make usage visible immediately.** Publish pending network records and combine them with cached
  persisted history for the selected range, updating as samples arrive rather than writing SQLite each second.
  Refresh network state and saved history on dashboard opening/activation and system wake. Use a revision
  check to discard stale async reads so a flush cannot temporarily double-count saved plus pending bytes.
- [x] **3. Show the actual name-discovery and storage state.** Distinguish permission needed, Location
  Services disabled, connected with name unavailable, disconnected, and off. Show an actionable explanation
  next to unattributed usage and surface read/write errors instead of displaying stale or empty history silently.
  Keep historic generic usage as recorded; do not automatically relabel it as the newly visible SSID.
- [x] **4. Correct network attribution.** Extract a small deterministic accounting component into
  `WiFiTrackerCore` with injected samples (counters, interface, connection/name state, and timestamps).
  Refresh connection identity alongside counters; evaluate documented Wi-Fi events, with polling fallback.
  Keep bytes from uncertain switch/gap intervals in an explicitly unattributed category, then baseline the
  new connection. Preserve aggregate bytes rather than dropping them at transitions. Treat reconnects,
  read failures, interface changes, name loss, and authorization changes as continuity changes where needed.
  Give unattributed records a distinct storage identity so a real SSID named `Wi-Fi` cannot collide with them.
- [x] **5. Make saves and recovery reliable.** Run the due-flush check independently of sample success.
  Persist network usage and the matching current counter checkpoint in one SQLite transaction. Keep per-app
  write failures from blocking a committed network-history update. Define a conservative migration from
  legacy UserDefaults checkpoints; preserve existing history. Recover closed/suspended-interval bytes as
  unattributed when network continuity cannot be established, even if the starting/ending SSIDs match.
  Change background activity policy only if an awake-state stall is demonstrated; allow normal Mac sleep.
- [x] **6. Add regression coverage and verify the bundled app.** Use Swift Testing, consistent with this
  native Swift project, and an isolated database/checkpoint. Do not run a second tracker against real history.
  Complete the checks below before proposing a release or replacing the installed app.

## Verification and acceptance criteria

- [x] While awake with readable names, a newly used network and its bytes appear within two sampling cycles
  (target ≤2–3 seconds); the view does not depend on the 60-second disk flush.
- [x] Dashboard opening and wake refresh paths are covered by regression tests; live dashboard opening was
  checked visually. A 15-minute awake/background run confirms no unexplained multi-minute sampling stall.
- [x] Missing SSIDs produce an explicit explanation and separate unattributed usage; enabling permission
  starts named accounting promptly once the OS returns the name, without rewriting older generic records.
- [x] A→B, A→disconnected→B, name loss/recovery, same-name reconnect, failed read/recovery, and interface
  replacement tests preserve expected download/upload totals without charging uncertain bytes to A or B.
- [x] Persisted-plus-pending history stays correct across flushes, range changes, failed writes, and slow/cancelled
  reads. A per-app failure does not hide successfully committed network usage.
- [x] Forced exit immediately after an automatic save followed by restart with unchanged counters recovers
  zero extra bytes. Changed-network and A→B→A closed intervals never falsely recover bytes to a known SSID.
- [x] Migration, clear-history, CSV export, compaction, real `Wi-Fi` SSID, and database failure tests preserve
  totals and distinct identities. All existing 33 tests continue to pass.
- [x] In an isolated bundled run, compare saved bytes and checkpoints with kernel counters and independent
  `netstat -ib` readings. Check background CPU use. Two physical networks were not available for this check.
- [ ] Optional interactive verification: switch between two real networks, accept the Location permission
  prompt, and repeat physical sleep/wake. Deterministic tests cover the corresponding accounting states.

## Review

- Implementation and available local verification are complete. All 93 tests pass (63 core + 30 app/model).
- Baseline tests pass with macOS kernel-counter access. The sandboxed run blocked `lo0` sysctl and failed
  that integration test; rerunning with the required access passed all 33 tests. Build/test output stayed in
  `/private/tmp/wifitracker-network-review`; no GUI tracker was launched.
- The strongest observed clue is prolonged recording under the generic name, with a separate one-minute
  display lag in the current design. The cause of the temporary SSID unavailability remains unconfirmed.
- Apple's documented event API requires the `com.apple.wifi.events` entitlement; verify availability with
  the project's signing/distribution before depending on it. See
  [CoreWLAN event registration](https://developer.apple.com/documentation/corewlan/cwwificlient/startmonitoringevent(with:)).
- App Nap can throttle background timers, but its involvement here is unconfirmed. See
  [Apple's App Nap guide](https://developer.apple.com/library/archive/documentation/Performance/Conceptual/power_efficiency_guidelines_osx/AppNap.html).

### Implementation review (2026-10-08)

- Network discovery now refreshes with every sample, with best-effort event notifications and polling fallback.
  Actual SSID availability is separate from authorization and global Location Services status; missing names
  show an explanation and count in a distinct unattributed category.
- Live history overlays pending records and cumulative hourly session commits over cached saved summaries.
  Revision, request, epoch, and cancellation checks reject stale reads. Clears reset the overlay epoch.
- Same-interface switches, disconnect/read/wake gaps, and restart recovery preserve comparable bytes as
  unattributed. Sleep-inclusive ContinuousClock timing and an explicit live-rate flag prevent gap bytes
  from inflating speeds or peaks. Failed reads still reach the due-save check.
- SQLite usage/checkpoint writes are atomic. Legacy rows remain unchanged, older UserDefaults checkpoints
  are deliberately not imported, clears take a fresh counter boundary, and corrupt checkpoints rebaseline
  without deleting saved history. Per-app save failures no longer block network history publication.
- Added 60 regressions across accounting, store, monitor, name availability, and deterministic history races.
  All 93 tests pass. Temporary boot-time failures and independent per-app write failures are covered.
- A consistent read-only backup of the real legacy database migrated through the actual UsageStore code:
  all 1,138 usage rows and 509 app rows match their pre-migration hashes; 9,314,076,566 bytes are preserved;
  SQLite quick_check is ok. The source database was not changed by this check.
- Visual verification covers live pending usage, unavailable-name explanations, and unattributed rows.
  Clean demo fixtures and a separate bundle identity keep new preview artifacts independent of real history.
- The universal release contains arm64 and x86_64, both with macOS 14.0 minimum. Its local DMG signature
  verifies and the packaged executable matches the release executable SHA-256 exactly.
- Runtime signing caught restricted `com.apple.wifi.events`: macOS rejected the ad-hoc build with AMFI -424
  despite a passing codesign verification. The entitlement was removed; polling remains the reliable fallback.
- Historical SSID unavailability cannot be explained retroactively. Diagnostics now record availability,
  permissions, samples, flushes, and reload timings without SSIDs. Two real-network switching and Location
  prompt acceptance still require an interactive check; deterministic regressions cover those state changes.
- No installed app, real network settings, published release, or existing usage records were modified.

- Runtime reference check: `netstat -ibn -I en0` counters fall between adjacent diagnostic readings in both
  directions. The completed 15-minute isolated background run produced 855 samples over 898.495 seconds,
  with no sampling gap exceeding 1.092 seconds. Saved usage equals checkpoint minus the initial kernel
  reading byte-for-byte: 26,118,823 downloaded and 27,564,887 uploaded bytes. SQLite quick_check is ok.
  The final checkpoint precedes termination by approximately 50 seconds, within the normal one-minute
  persistence interval; later samples remain pending until save or conservative restart recovery.
  A steady-state process check showed 0.1% CPU and about 66 MB RSS; this is not a formal energy measurement.
- Rendered clean demo history in dark mode at the 780-point minimum width: charts, totals, network bars,
  unavailable-name action, and unattributed explanation fit without clipping. Confirmed live network bytes
  appear in a snapshot about five seconds after sampling begins, before the normal one-minute save.
- Final local installer: `dist/WiFiTracker.dmg`. Mounted read-only and verified, then unmounted; packaged
  executable SHA-256 is 4d7b12e061ecb8fba59aa894514e7d264e3062952f2af4df855ea590b630a992.

### PR and fresh installer (2026-10-08)

User requested a PR and a new DMG after approving the implementation.

- [x] Check remote main, existing PRs, release versions, and packaging scripts.
- [x] Prepare version 1.0.1 and a focused fix branch.
- [ ] Rerun regression tests and build a fresh universal DMG from the committed application changes.
- [ ] Mount the installer read-only and verify its version, architectures, and signature.
- [ ] Push the branch, create the PR against main, and attach it to this chat.
- [ ] Provide the PR and local installer links.
