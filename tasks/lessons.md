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
