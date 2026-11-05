# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

The designed surface recorded here is the static landing site in `landing/`. The product itself is a native
macOS SwiftUI app (menu bar extra, dashboard, settings) in `app/`; its UI follows macOS conventions.

## Users

Curious Mac users who want to see what is using their bandwidth: which apps, how much, on which Wi-Fi network,
right now and over time. They arrive on the landing page wanting to know what the app shows and whether it is
safe to install. (Confirmed by the user, 2026-11-04.)

## Product Purpose

WiFi Tracker puts live Wi-Fi download and upload speeds in the menu bar and keeps a private, minute-by-minute
history of usage, split by app and by network. Success: a visitor understands what it shows within one
viewport, downloads it, and gets past the first-launch Gatekeeper step without fear.

## Positioning

It counts from the kernel's own 64-bit interface counters (the same source as `netstat -ib`), attributes traffic
to apps using macOS connection statistics (the same source as `nettop`), and splits it by Wi-Fi network. All of
it stays on the Mac: no account, no analytics, no network calls of its own.

## Operating Context

- Lives in the macOS menu bar; the dashboard is a separate window; the app stays out of the Dock.
- Speeds update every second; per-app figures are sampled every 2 seconds; history is stored per minute.
- Network names require Location Services access; without it usage is recorded under a generic Wi-Fi label.
- Distributed as an ad-hoc signed, non-notarized DMG from GitHub Releases; first launch needs
  System Settings › Privacy & Security › Open Anyway, or the `xattr` command.

## Capabilities and Constraints

- Menu bar display: both speeds, a combined figure, or just an icon; MB/s or Mbps.
- Dashboard: live chart (1/5/15 min); totals for today, this week, this month, all time; history for the last
  24 hours, 7 days, 30 days, 12 months; hover tooltips and a table view; per-network breakdown; apps ranked.
- Counts all traffic on the Wi-Fi interface (usually `en0`), including VPN traffic over Wi-Fi. Ethernet and
  iPhone USB tethering are not counted. Unattributable traffic is listed as "Other traffic".
- Catches up on traffic missed while quit, if the Mac has not restarted.
- History: SQLite at `~/Library/Application Support/WiFiTracker/`; Export CSV and Clear History in Settings.
- About 1 MB on disk, about 20 MB of memory. macOS 14 Sonoma or later, Apple silicon and Intel. Free, open source.
- The landing site is plain HTML/CSS/JS with no build step, deployed to GitHub Pages on push to `main`.

## Brand Commitments

- Name: "WiFi Tracker" (product), "Wi-Fi" (the network technology, in copy).
- Download is blue and upload is orange, everywhere: in the app and on the site.
- The landing page shows a live menu bar item and popover with simulated traffic, labeled as simulated.
- Factual copy is precise and numeric; it states the non-notarized first launch plainly.

## Evidence on Hand

- Dashboard and popover screenshots rendered by the app from synthetic demo data:
  `landing/assets/dashboard-light.png`, `landing/assets/dashboard-dark.png` (seeded by `scripts/seed-demo-data.mjs`).
- App icon: `landing/assets/icon.png`.
- Verified measurements in `tasks/todo.md` (counter accuracy vs `netstat`, CPU and memory).
- None exist and none may be invented: testimonials, customer logos, press, download counts, ratings.

## Product Principles

1. Show the real numbers; the product's own data is the proof.
2. Say exactly what is counted and what is not.
3. Private by construction: nothing leaves the Mac, and the site should not contradict that.
4. Small and native: it should feel like part of macOS, not a dashboard service.
