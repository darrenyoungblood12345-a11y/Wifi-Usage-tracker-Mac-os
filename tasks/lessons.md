# Lessons

_Patterns learned from corrections. Review at session start._

## 2026-10-07 — WiFi Tracker

- **Verify kernel APIs against a reference tool, not the header.** `NET_RT_IFLIST2`'s `if_data64` *looked* 64-bit
  but returned counters truncated to 32 bits (51.9 GB showed as 402 MB = 51.9 GB mod 2³²). Caught only by comparing
  with `netstat -ib`. The IFMIB sysctl (`net.link.generic.ifdata.<idx>.general`) is what netstat uses and is exact.
  Rule: for any counter/metric source, add an end-to-end check against the OS's own tool before trusting it.
- **Don't build/sign bundles inside iCloud-synced folders.** Desktop/Documents sync (File Provider) adds
  `com.apple.FinderInfo` to `.app`/`.xctest` bundles, which breaks `codesign` and invalidates existing signatures.
  Rule: put build products in `~/Library/Caches/...` (see `scripts/env.sh`) and stage DMGs with `ditto --noextattr`.
- **No Screen Recording permission → let the app render itself.** `NSView.cacheDisplay` of the app's own window
  (or an off-screen borderless window, which can exceed the display height) captures SwiftUI + Charts fine.
- **Scope text replacements to one occurrence.** A blanket `str.replace('<b>WiFi Tracker</b>', …)` meant for the
  landing page's faux menu bar also rewrote install step 2. Rule: replace with a unique surrounding context (or the
  Edit tool), then grep for the old and new strings to confirm the count.
- **Pages: upload and deploy in separate jobs.** `deploy-pages` run in the same job right after `upload-pages-artifact`
  found 0 artifacts (listing race). Follow GitHub's template: `build` job uploads, `deploy` job `needs: build`.

## 2026-10-07 — Per-app usage

- **Put dev env overrides on the launch command itself.** `cmd & … export WIFITRACKER_STORE=…` never reaches the
  already-started process, so a test bundle (same bundle ID → same UserDefaults checkpoint) ran against the real
  database and double-counted catch-up traffic. Rule: `WIFITRACKER_STORE=… cmd &` on one line, and confirm with
  `ps eww <pid> | grep WIFITRACKER_STORE` before measuring anything.
- **Measure a tool's steady-state cost before building on it.** `nettop` in logging mode (`-L 0`) busy-polls at
  ~130% CPU even with `-s`/`-c`; a one-shot `-L 1` costs ~15 ms. Its per-process figures only sum currently open
  sockets (they drop when a connection closes), so diff per socket, never per process.
- **Website screenshots must not leak the developer's SSID.** A preview can read the real network name even
  when authorization metadata suggests otherwise. Use explicit demo data and a demo header, then inspect
  the rendered artifact; an unbundled binary does not reliably prevent name access.

## 2026-10-08 — Delayed per-network usage

- **Treat "missing network" as a timing and identity question.** The user clarified that the network appeared
  after about 15 minutes. Rule: inspect the saved timeline and distinguish counter sampling, SSID availability,
  buffering, persistence, and view reload before choosing a fix. Traffic can continue under a generic label
  while the named row is absent; a permission flag alone does not prove that the SSID is readable.
- **Correlate long recording gaps with system sleep before blaming background throttling.** This database's
  long morning gaps lined up with sleep/dark-wake. Rule: establish an awake-state stall with timing evidence
  before adding activity assertions or changing power behavior.

- **A signature check does not prove macOS will launch the app.** Adding `com.apple.wifi.events` passed
  codesign verification but caused AMFI -424 on launch because the default build is ad-hoc signed.
  Rule: test launch with the project's real signing mode before depending on restricted entitlements;
  keep a documented polling fallback for network events.
- **Use observed SSID availability for the UI.** A verification process returned a readable name while
  CLLocationManager reported not determined. Rule: treat the actual name read as availability, retain
  authorization as a separate diagnostic/action state, and verify preview artifacts for private names.
- **Use a sleep-inclusive monotonic clock for traffic rates.** systemUptime can exclude sleep while kernel
  counters accrue traffic. Rule: preserve ContinuousClock timing and suppress live rates for recovered gaps;
  keep the bytes in usage without inventing a current speed or peak.
