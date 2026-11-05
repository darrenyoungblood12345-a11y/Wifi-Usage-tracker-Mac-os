---
target: landing page
total_score: 25
max_score: 36
na_heuristics: 7
p0_count: 0
p1_count: 3
target_identity: "file:/Users/darren/Desktop/code/Real Wifi tracker app/.claude/worktrees/beautiful-sutherland-227f0e/landing/index.html"
target_fingerprint: "sha256:086a6b20882932f4d41f978652a75201d31bc9e674e5176f29a673662de0a66d"
target_path: /Users/darren/Desktop/code/Real Wifi tracker app/.claude/worktrees/beautiful-sutherland-227f0e/landing/index.html
timestamp: 2026-11-05T02-31-05Z
slug: landing-index-html
---
⚠️ DEGRADED: single-context for Assessment A (sub-agent launch failed twice: tool safety check timed out); Assessment B ran as an isolated sub-agent after A was complete.

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|---|---|---|
| 1 | Visibility of System Status | 3 | "Last minute" chart empties after the tab returns from background, refills over 60 s |
| 2 | Match System / Real World | 3 | netstat, en0, SQLite, 64-bit kernel counters unexplained in feature cards |
| 3 | User Control and Freedom | 3 | Solid anchor nav; native details FAQ |
| 4 | Consistency and Standards | 3 | Three links to the same repo (nav GitHub, View source, footer) |
| 5 | Error Prevention | 2 | Not-notarized warning only in install step 3, below the fold, after 4 Download buttons |
| 6 | Recognition Rather Than Recall | 3 | Fine |
| 7 | Flexibility and Efficiency | n/a | No repeat-use accelerators on a landing page |
| 8 | Aesthetic and Minimalist Design | 2 | Every section below the hero has equal weight |
| 9 | Error Recovery | 3 | Copy-button fallback, static release fallback, Terminal route |
| 10 | Help and Documentation | 3 | FAQ answers the real questions |
| **Total** | | **25/36** | **Acceptable (69%)** |

## Design Specificity Verdict

Design review: the hero demo is authored; the rest is template (eyebrow/h1/lede/two buttons; centered h2 + grey paragraph x4 at 72px rhythm; 3x2 stroke-icon cards; three numbered step cards; +/- accordion; icon + slogan close). System-ui at 650-750, stock pastel gradient, one blue button; the app's blue/orange pairing only as 3px swatches. The per-app ranking, the most persuasive proof, appears only inside a scaled screenshot.

Deterministic scan: 10 findings, 2 rules. low-contrast x6 true (dark-mode buttons white on #3987e5 3.6:1; hover #5598e7 3.0:1). cramped-padding x4 false positives (deliberate macOS menubar/window chrome). Detector found nothing about template structure.

Visual overlays: skipped (read-only planning phase).

## What's Working
1. Live hero demo is real product material (true menu bar item + popover, Formatters.swift parity, realistic traffic scenes).
2. Copy uses numbers, not adjectives; discloses the non-notarized first launch.
3. Semantics, alt text, reduced motion, no overflow at 375, light/dark tokens.

## Priority Issues
- [P1] Template structure, category-interchangeable. Fix: let product artifacts (itemized per-app list, running byte total, network split) carry the structure. Command: new-work redesign.
- [P1] Best proof shown small, once, as a picture; unreadable at 375. Fix: render per-app/per-network breakdown as live HTML at reading size. Command: /impeccable bolder.
- [P1] Gatekeeper block comes after the download. Fix: one line under the primary CTA linking to install, show the dialog. Command: /impeccable clarify.
- [P2] Visual identity is system defaults. Fix: a face with a point of view; blue/orange at page scale. Commands: /impeccable typeset, /impeccable colorize.
- [P2] Dark-mode buttons fail contrast 3.6:1 / 3.0:1. Fix: darken to ~#2468c8 or dark text. Command: /impeccable polish.

## Persona Red Flags
- Jordan: "View source" second hero button competes with Download; jargon; Gatekeeper surprise.
- Riley: tab return empties the hero chart (path x 245-301 of 300); reduced motion freezes without notice.
- Casey: Download triggers a DMG on iPhone with no Mac-only note; first mobile screen all text, demo ~770px down; screenshot unreadable.

## Minor Observations
- One spacing rhythm and alignment throughout; no density change.
- Muddy dark wallpaper gradient (navy/plum/brown).
- h1 64px/750/-0.02em system-ui: default Apple-clone voice.
- Closing slogan instead of a real number.
- "Live preview with simulated traffic" caption is 13px muted, easy to miss.

## Questions to Consider
- What if the page were an itemized statement of where your data went?
- What if the only decoration allowed were real numbers?
- What if the running byte count, not the headline, were the first thing you read?
