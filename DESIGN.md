---
name: WiFi Tracker
description: Live Wi-Fi speeds in the menu bar and a private history of every megabyte, per app and per network.
colors:
  ground: "#ffffff"
  ink: "#000000"
  ink-secondary: "#3d3d3d"
  hairline: "rgba(0, 0, 0, 0.16)"
  download-blue: "#1f5fd6"
  upload-orange: "#ee6a2f"
  upload-ink: "#c94d17"
  band-black: "#000000"
  button-hover: "#262626"
  inverse-hover: "#e6eefb"
  ground-dark: "#0b0b0b"
  ink-dark: "#f5f5f2"
  ink-secondary-dark: "#b9b9b4"
  hairline-dark: "rgba(255, 255, 255, 0.2)"
  download-blue-dark: "#2a6bd1"
  download-ink-dark: "#6ea4f2"
  upload-orange-dark: "#f07a45"
  upload-ink-dark: "#f28a5c"
  button-hover-dark: "#d9d9d4"
typography:
  display:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(44px, 6.2vw, 96px)"
    fontWeight: 800
    lineHeight: 0.95
    letterSpacing: "-0.035em"
    fontVariation: "'wdth' 112"
  display-band:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(72px, 13vw, 200px)"
    fontWeight: 800
    lineHeight: 0.85
    letterSpacing: "-0.05em"
    fontVariation: "'wdth' 112"
  headline:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(32px, 3.8vw, 56px)"
    fontWeight: 800
    lineHeight: 1
    letterSpacing: "-0.03em"
    fontVariation: "'wdth' 110"
  figure:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(44px, 5.4vw, 80px)"
    fontWeight: 800
    lineHeight: 0.9
    letterSpacing: "-0.04em"
    fontVariation: "'wdth' 118"
    fontFeature: "'tnum' 1"
  numeral:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(72px, 9vw, 132px)"
    fontWeight: 800
    lineHeight: 0.85
    letterSpacing: "-0.05em"
  readout:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(26px, 2.8vw, 40px)"
    fontWeight: 750
    lineHeight: 1
    letterSpacing: "-0.02em"
    fontFeature: "'tnum' 1"
  title:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "20px"
    fontWeight: 700
    lineHeight: 1.3
  lede:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "clamp(19px, 1.6vw, 23px)"
    fontWeight: 400
    lineHeight: 1.4
  body:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.5
    fontFeature: "'tnum' 1"
  caption:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.5
  label:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "13px"
    fontWeight: 600
    letterSpacing: "0.02em"
  button:
    fontFamily: "Archivo, Helvetica Neue, Arial, sans-serif"
    fontSize: "18px"
    fontWeight: 700
    fontVariation: "'wdth' 105"
  mono:
    fontFamily: "ui-monospace, SF Mono, Menlo, monospace"
    fontSize: "0.85em"
rounded:
  none: "0px"
  macos-highlight: "4px"
  macos-popover: "12px"
spacing:
  margin: "clamp(16px, 3.2vw, 44px)"
  gutter: "clamp(12px, 1.8vw, 24px)"
  bar-gap: "3px"
  row: "20px"
  stack: "18px"
  hero-gap: "clamp(22px, 3vw, 36px)"
  band: "clamp(48px, 6vw, 80px)"
  section: "clamp(72px, 9vw, 128px)"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.ground}"
    typography: "{typography.button}"
    rounded: "{rounded.none}"
    padding: "15px 26px"
  button-primary-hover:
    backgroundColor: "{colors.button-hover}"
  button-inverse:
    backgroundColor: "{colors.ground}"
    textColor: "{colors.download-blue}"
    typography: "{typography.button}"
    rounded: "{rounded.none}"
    padding: "15px 26px"
  button-inverse-hover:
    backgroundColor: "{colors.inverse-hover}"
  button-copy:
    backgroundColor: "transparent"
    textColor: "{colors.ink}"
    rounded: "{rounded.none}"
    padding: "0 22px"
  code-row:
    backgroundColor: "{colors.band-black}"
    textColor: "{colors.ground}"
    typography: "{typography.mono}"
    rounded: "{rounded.none}"
    padding: "14px 16px"
  share-segment-download:
    backgroundColor: "{colors.download-blue}"
    textColor: "{colors.ground}"
    rounded: "{rounded.none}"
  share-segment-upload:
    backgroundColor: "{colors.upload-orange}"
    rounded: "{rounded.none}"
  share-tip:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.ground}"
    typography: "{typography.caption}"
    rounded: "{rounded.none}"
    padding: "10px 12px"
  menubar:
    backgroundColor: "{colors.band-black}"
    textColor: "{colors.ground}"
    typography: "{typography.label}"
    height: "30px"
  menubar-item:
    rounded: "{rounded.macos-highlight}"
    padding: "3px 9px"
  band-install:
    backgroundColor: "{colors.upload-orange}"
    textColor: "{colors.ink}"
    padding: "{spacing.band} 0"
  band-closing:
    backgroundColor: "{colors.download-blue}"
    textColor: "{colors.ground}"
    padding: "{spacing.band} 0"
---

# Design System: WiFi Tracker

## Overview

**Creative North Star: "The Proportional Chart"**

The site is a Swiss data-graphic printed at page scale. White ground and black ink carry everything that is not data; download blue and upload orange carry everything that is. The page's largest objects are full-bleed bars whose segment widths are bytes, and the same two colours return as whole bands (an orange Install field, a blue closing field) so the page reads as one chart from top to bottom. Typography is one family, Archivo, used heavy and expanded for display and at normal width for reading, with tabular figures throughout.

Density is poster-like: few elements, very large, flush left on a 12-column grid, separated by rules rather than boxes. Nothing floats. There are no cards, no shadows, no gradients and no rounded corners on the page's own surfaces. The only soft, layered, rounded object is the macOS menu bar popover, which is the product drawn as macOS draws it and keeps macOS's own material; it is a specimen on the page, not part of the page's component language.

Dark mode inverts ground and ink (near-black ground, warm off-white ink) and lifts the blue and orange slightly so the fields keep their weight; the menu bar and footer stay black in both schemes.

**Key Characteristics:**
- White (near-black) ground, black (off-white) ink, blue and orange as the only hues.
- Full-bleed proportional share bars as the signature graphic; segments resize as bytes arrive.
- Archivo 800, expanded 110–118% for headings and fact figures; normal width for text and live numbers.
- 12-column grid, flush left, 3px ink rules opening lists and 1px hairlines between rows.
- Flat and square: no shadows, no radius, no cards outside the macOS specimen.

## Colors

A two-hue data palette on a black-and-white page: colour means bytes.

### Primary
- **Download Blue** (download-blue; download-blue-dark in dark mode): download segments of every share bar, the closing band, the "Download" key swatch, and the focus ring. In dark mode the field lifts to download-blue-dark while blue text (the "Down now" readout, focus ring) uses the lighter download-ink-dark for contrast.

### Secondary
- **Upload Orange** (upload-orange; upload-orange-dark in dark mode): upload segments, the Install band, the "Upload" key swatch, and text selection. Black ink sits on it, never white.
- **Burnt Upload Ink** (upload-ink; upload-ink-dark in dark mode): orange used as text, for the "Up now" readout, where the field orange is too light to read on white.

### Neutral
- **Paper White** (ground) / **Night Ground** (ground-dark): the page.
- **Press Black** (ink) / **Warm Off-White** (ink-dark): headings, body, rules, the primary button, tooltips.
- **Graphite** (ink-secondary) / **Ash** (ink-secondary-dark): captions, answers, fact text, meta lines.
- **Hairline** (hairline / hairline-dark): 1px row separators and the dashboard screenshot frame. Inside the orange band it darkens to rgba(0, 0, 0, 0.3).
- **Band Black** (band-black): the menu bar band, the footer, and the terminal code row, in both schemes.

### Named Rules
**The Bytes Are Colour Rule.** Blue is download and orange is upload, everywhere, including the app. They appear as solid data segments, full-bleed fields, keys, and the down/up readouts; never as tints, gradients, or decoration, and no third hue is introduced.

**The Ink On Orange Rule.** Text on upload orange is black; text on download blue is white.

## Typography

**Display Font:** Archivo variable, self-hosted (with Helvetica Neue, Arial, sans-serif)
**Body Font:** Archivo at normal width (same fallback)
**Label/Mono Font:** ui-monospace, SF Mono, Menlo for commands and paths

**Character:** One grotesque doing two jobs: heavy and wide for poster headlines and fact figures, plain and normal-width for reading. Every figure on the page is tabular.

### Hierarchy
- **Display** (800, clamp 44–96px, 0.95, wdth 112): the hero headline, nine columns wide.
- **Display Band** (800, clamp 72–200px, 0.85, wdth 112): the single figure in the closing blue band, one line.
- **Headline** (800, clamp 32–56px, 1.0, wdth 110): section headings.
- **Figure** (800, clamp 44–80px, 0.9, wdth 118): the large values in fact rows ("1 s", "12 mo", "1 MB").
- **Numeral** (800, clamp 72–132px, 0.85, normal width): install step counters.
- **Readout** (750, clamp 26–40px, 1.0, normal width): live "Down now / Up now" speeds, coloured by direction. Segment amounts use the same weight-and-width logic at clamp 18–26px (26–44px on the network bar).
- **Title** (700, 20px, 1.3): fact titles, question terms and install step titles.
- **Lede** (400, clamp 19–23px, 1.4, max 34em): the hero sentence.
- **Body** (400, 17px, 1.5): running text; answers cap at 44em, step text at 30em.
- **Caption** (400, 14px): chart captions, figcaptions, Gatekeeper and meta lines, tooltips.
- **Label** (600, 13px, +0.02em): readout labels; the menu bar runs 13px at 500, the app name at 800 and wdth 110.

### Named Rules
**The Width Rule.** Headings and static fact figures run Archivo 800 expanded 110–118%. Live readouts, segment amounts and step numerals stay at normal width. Body text is never expanded.

**The Tabular Rule.** Figures are tabular everywhere (set on the body), so live numbers change without the line moving.

## Layout

A 12-column grid with fluid outer margin (clamp 16–44px) and gutter (clamp 12–24px), flush left. Share bars ignore the margin and run edge to edge with 3px gaps between segments; the app bar is clamp 220–340px tall (about 30vh), the network bar clamp 150–220px. Content splits asymmetrically across the columns: headline 9 + readouts 3; lede 6 + action 5 starting at column 8; section heading 8 + note 4; fact rows 4 (figure) + 3 (title) + 5 (text); questions 5 + 7; dashboard copy 4 (sticky) + screenshot 8.

Vertical rhythm: sections are separated by clamp 72–128px; coloured bands pad clamp 48–80px; ruled rows pad 18–22px; stacked prose steps 18px. The menu bar is a 30px sticky band.

Responsive: at 760px and below every grid child spans all 12 columns, the menu bar hides its section menus and clock, and share bars turn on their side into stacked proportional rows (height grows with share, minimum 34px), labels inline on the blue. At 1500px and above the menu bar popover opens by default at the right edge, the readouts move under the headline, and the hero head grows to at least 350px so the chart starts below the popover.

## Elevation & Depth

Flat. The page has no shadows and no layered surfaces; depth comes from full-bleed colour fields and the weight difference between 3px ink rules and 1px hairlines. The tooltip is a solid ink block with no shadow. The macOS popover alone carries translucency, backdrop blur and a soft two-layer shadow, because that is how macOS draws it.

### Named Rules
**The Flat Field Rule.** Page surfaces are separated by colour fields and rules, never by elevation. Shadows and blur belong only to things drawn as macOS draws them.

## Shapes

Square. Every page surface (bars, buttons, bands, tooltip, code row, screenshot frame) has 0 radius. Rounded corners appear only where macOS itself rounds: menu bar item highlights (4px) and the popover (12px, with its 6–7px rows and tiles). Rules are the recurring geometry: a 3px ink rule opens each list (facts, questions, each install step), and 1px hairlines close each row.

### Named Rules
**The Square Corner Rule.** If it is the page, it is square. If it is macOS, it keeps macOS's radius.

**The Two Rules Rule.** 3px ink opens a list; 1px hairline separates its rows. No boxes.

## Components

### Buttons
Blunt, square, heavy.
- **Shape:** square corners (0).
- **Primary:** solid ink block, ground-coloured text, Archivo 700 18px at wdth 105, 15px × 26px padding, an 18px stroked download arrow before the label.
- **Hover / Focus:** background eases to button-hover over 0.15s; pressed state drops 1px; focus is a 3px outline offset 2px in the focus colour (white inside the blue band, black inside the orange band).
- **Inverse:** on the blue closing band the button flips to a white block with blue text, hovering to a pale blue.
- **Copy:** a 3px black outline button joined flush to the black code row inside the orange band; hover adds a 10% black wash.

### Share Bar (signature)
A full-bleed ordered list of segments whose flex-grow is each item's share of total bytes. Each segment stacks its download (blue) over its upload (orange) portion in proportion. Labels (name 14px 600, amount in the readout style) sit inside on the blue, top-left; when a segment is too narrow they turn vertical, and when even that does not fit they hide while still being measured so they return. Shares animate over 0.9s on cubic-bezier(0.16, 1, 0.3, 1); reduced motion removes the transition. Hover brightens the blue 12%; hover or keyboard focus shows a square ink tooltip with exact total, down, up and live rate. Each segment is focusable with an ink focus ring and a full aria-label. Captions below state what width means and say "Simulated."

### Keys
Inline 11px square swatches before "Download" and "Upload" labels in captions, 600 weight in ink.

### Ruled Rows (facts and questions)
Grid rows under a 3px ink rule, each closed by a 1px hairline, padded 18–22px. Facts pair an expanded figure, a title and secondary-ink text; questions pair a title-weight term with a secondary-ink answer.

### Install Steps
Three four-column steps under 3px black rules in the orange band, each led by a huge normal-width counter numeral, a 20px title, and short text.

### Navigation (menu bar band)
A sticky 30px black band drawn like the macOS menu bar: app name in 800 expanded, section links at 13px 500, and the live status item ("↓rate ↑rate", the app's own menu bar format) on the right. Items highlight with a 4px-rounded 18% white wash on hover or when open; the status item toggles the popover. In dark mode the band gains a 1px hairline bottom edge.

### Coloured Bands
Full-bleed fields that carry whole sections: upload orange for Install (black ink, black selection and focus), download blue for the closing figure (white ink). The footer is a black band with 15px links.

### macOS Popover (product specimen)
The app's menu bar popover reproduced in the system font with macOS translucency, 12px radius and its own palette. Documented only so it is not mistaken for the page's language; nothing outside it borrows its radius, blur, shadow or font.

## Do's and Don'ts

### Do:
- **Do** let data set size: widths and heights of share segments are byte shares, never chosen for layout.
- **Do** keep blue for download and orange for upload in every chart, key, readout and field.
- **Do** separate content with the 3px ink rule and 1px hairline, flush left on the 12-column grid.
- **Do** run headings Archivo 800 expanded (wdth 110–118) and keep live numbers normal width and tabular.
- **Do** label every segment across, then on its side, then via tooltip, as a printed chart would.
- **Do** put black ink on orange and white ink on blue.
- **Do** mark simulated data as "Simulated." in the caption beside it.

### Don't:
- **Don't** use cards, boxed containers, or drop shadows on page surfaces.
- **Don't** round page corners; radius is reserved for elements drawn as macOS draws them.
- **Don't** introduce a third hue, tints of blue or orange, or gradients.
- **Don't** expand body text or set live, changing numbers in proportional figures.
- **Don't** borrow the popover's blur, shadow, radius or system font for page components.
