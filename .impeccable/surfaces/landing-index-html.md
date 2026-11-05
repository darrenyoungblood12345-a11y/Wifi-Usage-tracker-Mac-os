---
version: 1
slug: "landing-index-html"
primary_target: "landing/index.html"
related_targets: ["landing/styles.css","landing/main.js"]
---

## Scope

The public landing page: `landing/index.html`, `landing/styles.css`, `landing/main.js`, self-hosted Archivo in
`landing/fonts/`. Mode: Persuade. Code-led build (no image generation); a working Poster sample was the comp
the user chose on 2026-11-04 over Statement and Meter. All three samples were removed from the repo at the
user's request once Poster shipped.

## Brief

- Audience: curious Mac users who want to see what is using their bandwidth.
- Job: show per-app and per-network usage working before asking for anything.
- Action: download the DMG, knowing about the one-time Gatekeeper click before it happens.
- Proof: the live simulated menu bar and share bars (labelled simulated), the app-rendered dashboard
  screenshot, version/size/requirements, open source.
- Constraints: every factual sentence word for word from the previous page; blue = download, orange = upload;
  no invented testimonials, logos, or numbers; the page fetches only GitHub release info.

## Direction contract

THESIS: The page is one proportional chart of where a Mac's Wi-Fi went today; the bytes are the hero. It refuses
the category default of icon hero + floating screenshot + 3×2 feature cards + pastel gradient.

OWN-WORLD: Swiss data-graphic. White ground (near-black in dark), black ink, download blue and upload orange as
page-scale fields: full-bleed share bars, an orange Install band, a blue closing band, a black menu-bar band.
Archivo 800 expanded 110–118% for display, normal width for text, tabular figures. 12-column grid, flush left,
hairline rules, no cards, no shadows, no rounding except the macOS popover.

STORY: The visitor watches live bytes split by app and network, learns it reads kernel counters and stays on the
Mac, sees the real dashboard, and downloads the 1 MB DMG knowing the extra Privacy & Security click.

FIRST VIEWPORT: Black menu-bar band with section menus and the live status item (popover open at ≥1500px). A
9-column h1 at 44–96px with Down now / Up now readouts beside it (under it at ≥1500px, where the head grows so
the chart starts below the open popover); a full-bleed app share bar about 30vh tall with every segment labelled,
on its side when narrow; caption; lede left, black Download for Mac button right with the Gatekeeper line and
meta below. On phones the bar becomes stacked proportional rows. Signature: segments widen as bytes arrive;
hover or focus shows exact down/up and live rate.

FORM: Poster, the third of three directions (Statement, Meter, Poster) built as working samples.
seed: none (no roll ran: the user pinned the range, answering "Three new worlds", approved the three named
directions in the plan, then chose "Poster")

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

## Unresolved

- None.
