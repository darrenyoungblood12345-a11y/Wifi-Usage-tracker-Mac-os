// WiFi Tracker landing page. The menu bar demo and the share bars run on one simulated traffic feed; every
// figure it produces is simulated, and the page labels it that way.

const REPO = 'darrenyoungblood12345-a11y/Wifi-Usage-tracker-Mac-os'
const DMG_NAME = 'WiFiTracker.dmg'
const IS_LOCAL = ['localhost', '127.0.0.1', ''].includes(location.hostname)

const REPO_URL = `https://github.com/${REPO}`
const DOWNLOAD_URL = IS_LOCAL
  ? new URL(`downloads/${DMG_NAME}`, import.meta.url).href
  : `${REPO_URL}/releases/latest/download/${DMG_NAME}`

const $$ = (selector, root = document) => [...root.querySelectorAll(selector)]

// Formatting mirrors the app's Formatters.swift: decimal units, three significant digits.

const threeSignificantDigits = (value) =>
  value < 9.995 ? value.toFixed(2) : value < 99.95 ? value.toFixed(1) : value.toFixed(0)

const scaled = (value, units, minimumUnit = false) => {
  const [amount, unit] = units
    .slice(1)
    .reduce(([current, currentUnit], next) => (current >= 999.5 ? [current / 1000, next] : [current, currentUnit]), [value / 1000, units[0]])
  if (minimumUnit && amount < 0.05) return `0 ${unit}`
  return `${threeSignificantDigits(amount)} ${unit}`
}

const formatBytes = (bytes) => (bytes < 1000 ? `${Math.round(bytes)} B` : scaled(bytes, ['KB', 'MB', 'GB', 'TB']))
const formatRate = (bytesPerSecond) => scaled(Math.max(0, bytesPerSecond), ['KB/s', 'MB/s', 'GB/s'], true)
const totalOf = ({ down, up }) => down + up

const motionQuery = matchMedia('(prefers-reduced-motion: reduce)')
const prefersReducedMotion = () => motionQuery.matches

/** iPadOS reports a Macintosh user agent, so touch points tell the two apart. */
const isMacVisitor = () => /Macintosh/.test(navigator.userAgent) && navigator.maxTouchPoints < 2

// Seed totals: the last 24 hours from the demo database the app renders its own screenshots from.

const MB = 1e6

const APPS = [
  { id: 'safari', name: 'Safari', down: 926 * MB, up: 104 * MB },
  { id: 'chrome', name: 'Google Chrome', down: 574 * MB, up: 77.2 * MB },
  { id: 'music', name: 'Music', down: 382 * MB, up: 9.31 * MB },
  { id: 'facetime', name: 'FaceTime', down: 209 * MB, up: 144 * MB },
  { id: 'tv', name: 'TV', down: 330 * MB, up: 4.17 * MB },
  { id: 'appstore', name: 'App Store', down: 181 * MB, up: 2.87 * MB },
  { id: 'photos', name: 'Photos', down: 89.9 * MB, up: 54.6 * MB },
  { id: 'mail', name: 'Mail', down: 109 * MB, up: 24.5 * MB },
  { id: 'nsurlsessiond', name: 'nsurlsessiond', down: 59.4 * MB, up: 8.94 * MB },
  { id: 'softwareupdated', name: 'softwareupdated', down: 66.3 * MB, up: 1.02 * MB },
  { id: 'other', name: 'Other traffic', down: 155 * MB, up: 22.9 * MB },
]

// Networks add up to the same total as the apps, as they do in the app ("Other traffic" closes the gap).
const sum = (list, key) => list.reduce((total, item) => total + item[key], 0)
const OFFICE = { id: 'office', name: 'Office', down: 1130 * MB, up: 156 * MB }
const NETWORKS = [
  { id: 'home', name: 'Home Wi-Fi', down: sum(APPS, 'down') - OFFICE.down, up: sum(APPS, 'up') - OFFICE.up },
  OFFICE,
]

const CURRENT_NETWORK = 'home'

// Traffic shaped like real use. Each scene says which apps its bytes belong to.

const SCENES = [
  {
    name: 'idle', duration: [4, 8], down: [6e3, 40e3], up: [2e3, 12e3], jitter: 0.6,
    shares: [{ music: 0.35, nsurlsessiond: 0.2, mail: 0.15, safari: 0.1, other: 0.2 }],
  },
  {
    name: 'browsing', duration: [3, 5], down: [0.6e6, 2.8e6], up: [40e3, 160e3], jitter: 0.5,
    shares: [{ safari: 0.92, other: 0.08 }, { chrome: 0.92, other: 0.08 }],
  },
  {
    name: 'streaming', duration: [8, 13], down: [1.6e6, 2.4e6], up: [25e3, 60e3], jitter: 0.15,
    shares: [{ tv: 0.95, other: 0.05 }],
  },
  {
    name: 'download', duration: [5, 9], down: [6e6, 8.5e6], up: [120e3, 260e3], jitter: 0.08,
    shares: [{ appstore: 0.95, other: 0.05 }, { softwareupdated: 0.95, other: 0.05 }],
  },
  {
    name: 'call', duration: [8, 12], down: [350e3, 500e3], up: [300e3, 450e3], jitter: 0.15,
    shares: [{ facetime: 0.93, other: 0.07 }],
  },
  {
    name: 'photo sync', duration: [6, 10], down: [80e3, 240e3], up: [1.2e6, 2.6e6], jitter: 0.2,
    shares: [{ photos: 0.94, other: 0.06 }],
  },
]

const between = ([low, high]) => low + Math.random() * (high - low)
const pick = (list) => list[Math.floor(Math.random() * list.length)]

const createTraffic = () => {
  let scene = SCENES[0]
  let shares = scene.shares[0]
  let remaining = 0
  let base = { down: 0, up: 0 }
  let last = { down: 20e3, up: 6e3 }

  const nextScene = () => {
    scene = scene === SCENES[0] ? pick(SCENES.slice(1)) : SCENES[0]
    shares = pick(scene.shares)
    remaining = Math.round(between(scene.duration))
    base = { down: between(scene.down), up: between(scene.up) }
  }

  return () => {
    if (remaining <= 0) nextScene()
    remaining -= 1
    const wobble = () => 1 + scene.jitter * (Math.random() * 2 - 1)
    // Ease toward the target so transitions ramp like real TCP flows.
    last = {
      down: last.down + (base.down * wobble() - last.down) * 0.65,
      up: last.up + (base.up * wobble() - last.up) * 0.65,
    }
    return { ...last, shares, scene: scene.name }
  }
}

/** Apps by total, largest first; "Other traffic" always last, as in the app. */
const rankApps = (apps) =>
  [...apps].sort((a, b) => (a.id === 'other') - (b.id === 'other') || totalOf(b) - totalOf(a))

const MAX_CATCH_UP_SECONDS = 3600

/**
 * One simulated sample per second. If the tab was in the background (where browsers throttle timers),
 * the missed seconds are generated on return, so the last-minute chart is never left empty.
 */
const createLiveFeed = ({ windowSeconds = 60 } = {}) => {
  const nextSample = createTraffic()
  const keep = (windowSeconds + 2) * 1000

  const step = (state, sample, time) => {
    const portion = (id) => sample.shares[id] ?? 0
    return {
      time,
      scene: sample.scene,
      rate: { down: sample.down, up: sample.up },
      samples: [...state.samples.filter((point) => point.time > time - keep), { time, down: sample.down, up: sample.up }],
      today: { down: state.today.down + sample.down, up: state.today.up + sample.up },
      apps: state.apps.map((app) => ({
        ...app,
        down: app.down + sample.down * portion(app.id),
        up: app.up + sample.up * portion(app.id),
        rateDown: sample.down * portion(app.id),
        rateUp: sample.up * portion(app.id),
      })),
      networks: state.networks.map((network) =>
        network.id === CURRENT_NETWORK
          ? { ...network, down: network.down + sample.down, up: network.up + sample.up, current: true }
          : network,
      ),
    }
  }

  const start = Date.now()
  const initial = {
    time: start - (windowSeconds + 1) * 1000,
    samples: [],
    today: { down: 1.11e9, up: 0.128e9 },
    apps: APPS.map((app) => ({ ...app, rateDown: 0, rateUp: 0 })),
    networks: NETWORKS.map((network) => ({ ...network, current: network.id === CURRENT_NETWORK })),
  }
  // Pre-fill the chart window without counting it toward the totals, so the page opens on a full minute.
  const prefilled = Array.from({ length: windowSeconds + 1 }).reduce(
    (state, _, index) => step(state, nextSample(), initial.time + (index + 1) * 1000),
    initial,
  )
  let state = {
    ...initial,
    time: prefilled.time,
    scene: prefilled.scene,
    rate: prefilled.rate,
    samples: prefilled.samples,
    apps: initial.apps.map((app, index) => ({ ...app, rateDown: prefilled.apps[index].rateDown, rateUp: prefilled.apps[index].rateUp })),
  }

  const listeners = new Set()
  let timer = 0

  const tick = () => {
    const now = Date.now()
    const due = Math.min(Math.floor((now - state.time) / 1000), MAX_CATCH_UP_SECONDS)
    if (due <= 0) return
    const base = now - state.time > MAX_CATCH_UP_SECONDS * 1000 ? now - due * 1000 : state.time
    state = Array.from({ length: due }).reduce((current, _, index) => step(current, nextSample(), base + (index + 1) * 1000), state)
    listeners.forEach((listener) => listener(state))
  }

  const run = () => {
    if (timer) return
    timer = setInterval(tick, 1000)
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') tick()
    })
  }

  return {
    windowSeconds,
    current: () => state,
    subscribe: (listener) => {
      listeners.add(listener)
      listener(state)
      run()
      return () => listeners.delete(listener)
    },
  }
}

// The menu bar status item and popover.

/** Download/upload arrows drawn as SVG, for use outside the menu bar text (where the app itself prints ↓ ↑). */
const arrowSvg = (direction, className = '') =>
  `<svg class="${className}" viewBox="0 0 10 10" width="10" height="10" aria-hidden="true" focusable="false"><path d="${
    direction === 'down' ? 'M5 1.2v7M2 5.2l3 3 3-3' : 'M5 8.8v-7M2 4.8l3-3 3 3'
  }" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg>`

const WIFI_ICON = `<svg viewBox="0 0 24 24" width="16" height="16" focusable="false"><path d="M2.5 9a14 14 0 0 1 19 0M5.8 12.4a9.5 9.5 0 0 1 12.4 0M9.1 15.8a4.7 4.7 0 0 1 5.8 0" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/><circle cx="12" cy="19.2" r="1.6" fill="currentColor"/></svg>`

const CHART_ICON = `<svg viewBox="0 0 16 16" aria-hidden="true" focusable="false"><path d="M2 14h12M4 11V7M8 11V3M12 11V8" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/></svg>`

const POPOVER_HTML = `
  <div class="pop-network">
    <span class="pop-wifi" aria-hidden="true">${WIFI_ICON}</span>
    <span><strong>Home Wi-Fi</strong><small>Connected · en0</small></span>
  </div>
  <div class="pop-rates">
    <div><span class="pop-key"><i class="pop-swatch"></i>Download</span><span class="pop-rate" data-live="rate-down"></span></div>
    <div><span class="pop-key"><i class="pop-swatch pop-swatch-up"></i>Upload</span><span class="pop-rate" data-live="rate-up"></span></div>
  </div>
  <p class="pop-label">Last minute</p>
  <svg class="pop-spark" viewBox="0 0 300 70" preserveAspectRatio="none" role="img" aria-label="Simulated download and upload speed over the last minute" data-spark-chart>
    <path data-spark="area-download"/><path data-spark="area-upload"/><path data-spark="line-download"/><path data-spark="line-upload"/>
  </svg>
  <div class="pop-today">
    <span><small>Used today</small><strong data-live="today-total"></strong></span>
    <span class="pop-split">
      <span><span data-live="today-down"></span>${arrowSvg('down', 'pop-arrow')}</span>
      <span><span data-live="today-up"></span>${arrowSvg('up', 'pop-arrow pop-arrow-up')}</span>
    </span>
  </div>
  <a class="pop-row" href="#dashboard">${CHART_ICON}Open Dashboard</a>
  <p class="pop-note">Simulated traffic, shaped like real use.</p>`

const createSpark = (svg, windowSeconds) => {
  const [, , width, height] = svg.getAttribute('viewBox').split(/\s+/).map(Number)
  const part = (name) => svg.querySelector(`[data-spark="${name}"]`)
  const parts = [
    ['down', part('line-download'), part('area-download')],
    ['up', part('line-upload'), part('area-upload')],
  ]
  let yMax = 0

  /** Smooth path through points (Catmull-Rom → cubic Bézier), clamped so curves never dip below the baseline. */
  const smoothPath = (points, floor) =>
    points.reduce((path, [x, y], index) => {
      if (index === 0) return `M${x.toFixed(1)},${y.toFixed(1)}`
      const [x0, y0] = points[index - 2] ?? points[index - 1]
      const [x1, y1] = points[index - 1]
      const [x3, y3] = points[index + 1] ?? [x, y]
      const c1 = [x1 + (x - x0) / 6, Math.min(floor, y1 + (y - y0) / 6)]
      const c2 = [x - (x3 - x1) / 6, Math.min(floor, y - (y3 - y1) / 6)]
      return `${path} C${c1[0].toFixed(1)},${c1[1].toFixed(1)} ${c2[0].toFixed(1)},${c2[1].toFixed(1)} ${x.toFixed(1)},${y.toFixed(1)}`
    }, '')

  return ({ samples }, time, { ease }) => {
    const target = Math.max(...samples.map(({ down, up }) => Math.max(down, up))) * 1.15 || 1
    yMax = yMax === 0 || !ease ? target : yMax + (target - yMax) * 0.08
    const x = (sampleTime) => width - ((time - sampleTime) / 1000 / windowSeconds) * width
    const y = (value) => height - 2 - (value / yMax) * (height - 6)
    parts.forEach(([key, line, area]) => {
      const points = samples.map((sample) => [x(sample.time), y(sample[key])])
      const d = smoothPath(points, height - 2)
      line?.setAttribute('d', d)
      area?.setAttribute('d', `${d} L${points.at(-1)[0].toFixed(1)},${height} L${points[0][0].toFixed(1)},${height} Z`)
    })
  }
}

const clockText = () => new Date().toLocaleString(undefined, { weekday: 'short', hour: 'numeric', minute: '2-digit' })

const setText = (nodes, value) =>
  nodes.forEach((node) => {
    if (node.textContent !== value) node.textContent = value
  })

const wirePopover = (button) => {
  const popover = document.getElementById(button.getAttribute('aria-controls'))
  if (!popover) return
  const setOpen = (open) => {
    button.setAttribute('aria-expanded', String(open))
    popover.hidden = !open
  }
  setOpen(matchMedia(button.dataset.openAt ?? 'all').matches)
  button.addEventListener('click', () => setOpen(popover.hidden))
  document.addEventListener('keydown', (event) => {
    if (event.key !== 'Escape' || popover.hidden) return
    const hadFocus = popover.contains(document.activeElement)
    setOpen(false)
    if (hadFocus) button.focus()
  })
}

const mountMenuBar = (feed) => {
  $$('[data-popover-slot]').forEach((slot) => { slot.innerHTML = POPOVER_HTML })
  const nodes = (key) => $$(`[data-live="${key}"]`)
  const fields = {
    'rate-down': ({ rate }) => formatRate(rate.down),
    'rate-up': ({ rate }) => formatRate(rate.up),
    'today-total': ({ today }) => formatBytes(totalOf(today)),
    'today-down': ({ today }) => formatBytes(today.down),
    'today-up': ({ today }) => formatBytes(today.up),
    clock: () => clockText(),
  }
  const bound = Object.entries(fields).map(([key, format]) => [nodes(key), format])
  const sparks = $$('svg[data-spark-chart]').map((svg) => [svg, createSpark(svg, feed.windowSeconds)])
  const reduced = prefersReducedMotion()
  let latest = null

  feed.subscribe((state) => {
    latest = state
    bound.forEach(([targets, format]) => setText(targets, format(state)))
    if (reduced) sparks.forEach(([, draw]) => draw(state, state.time, { ease: false }))
  })

  $$('[data-popover-toggle]').forEach(wirePopover)

  if (reduced) return
  // Scroll continuously, lagging one second so the newest point slides in from the right edge.
  const frame = () => {
    sparks.forEach(([svg, draw]) => {
      if (latest && svg.getClientRects().length) draw(latest, Date.now() - 1000, { ease: true })
    })
    requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)
}

// Links, copy buttons, release info, and the Mac-only and reduced-motion notes.

const wireCopyButtons = () =>
  $$('[data-copy]').forEach((button) => {
    const label = button.textContent
    button.addEventListener('click', async () => {
      const text = document.getElementById(button.dataset.copy)?.textContent ?? ''
      try {
        await navigator.clipboard.writeText(text)
        button.textContent = 'Copied'
      } catch {
        button.textContent = 'Select & copy'
      }
      setTimeout(() => { button.textContent = label }, 1600)
    })
  })

/** Shows the real version and size once a release exists; the static text stays as the fallback. */
const loadReleaseInfo = async () => {
  try {
    const response = await fetch(`https://api.github.com/repos/${REPO}/releases/latest`, {
      headers: { Accept: 'application/vnd.github+json' },
    })
    if (!response.ok) return
    const release = await response.json()
    const version = String(release.tag_name ?? '').replace(/^v/, '')
    const asset = (release.assets ?? []).find(({ name }) => name === DMG_NAME)
    if (version) {
      $$('[data-release-version]').forEach((node) => {
        node.textContent = node.dataset.releaseVersion === 'bare' ? version : `Version ${version}`
      })
    }
    if (asset?.size) $$('[data-release-size]').forEach((node) => { node.textContent = formatBytes(asset.size) })
  } catch {
    // Offline or rate-limited: keep the static text.
  }
}

const wireCommon = () => {
  $$('[data-download]').forEach((link) => link.setAttribute('href', DOWNLOAD_URL))
  $$('[data-repo]').forEach((link) => link.setAttribute('href', REPO_URL))
  $$('[data-releases]').forEach((link) => link.setAttribute('href', `${REPO_URL}/releases`))
  $$('[data-mac-note]').forEach((node) => { node.hidden = isMacVisitor() })
  $$('[data-motion-note]').forEach((node) => { node.hidden = !prefersReducedMotion() })
  wireCopyButtons()
  loadReleaseInfo()
}

// The share bars: one full-width bar per breakdown, split by how much each app or network used.

const $ = (selector) => document.querySelector(selector)

const feed = createLiveFeed()

const describe = (item) =>
  `${item.name}: ${formatBytes(totalOf(item))}, ${formatBytes(item.down)} down, ${formatBytes(item.up)} up`

const tipHtml = (item) => {
  const rate = (item.rateDown ?? 0) + (item.rateUp ?? 0)
  const now = rate < 50 ? 'idle now' : `${formatRate(rate)} now`
  return `<b>${item.name} · ${formatBytes(totalOf(item))}</b>${formatBytes(item.down)} down · ${formatBytes(item.up)} up · ${now}`
}

const fitsAcross = (segment) => {
  const name = segment.querySelector('.seg-name')
  const amount = segment.querySelector('.seg-amount')
  return segment.clientWidth >= Math.max(name.scrollWidth, amount.scrollWidth) + 16
}

/** A label on its side has to fit the segment's width and stay on the blue download part. */
const fitsDown = (segment) => {
  const label = segment.querySelector('.seg-label')
  const download = segment.querySelector('.seg-down')
  return segment.clientWidth >= label.offsetWidth + 6 && download.clientHeight >= label.offsetHeight + 20
}

/**
 * Label every segment the way a printed chart would: across when it fits, on its side when the segment
 * is narrow, and hidden only when even that does not fit (the tooltip still has the figures).
 */
const fitLabel = (segment) => {
  segment.classList.remove('is-vertical', 'is-narrow')
  if (fitsAcross(segment)) return
  segment.classList.add('is-vertical')
  if (fitsDown(segment)) return
  segment.classList.replace('is-vertical', 'is-narrow')
}

/** A full-width bar split into one segment per item; width is the item's share of the total. */
const createShareBar = (list) => {
  const figure = list.closest('figure')
  const tip = figure.querySelector('[data-tip]')
  const segments = new Map()
  const items = new Map()
  let active = null

  const placeTip = (segment) => {
    const vertical = getComputedStyle(list).flexDirection === 'column'
    tip.hidden = false
    if (vertical) {
      tip.style.left = '12px'
      tip.style.top = `${segment.offsetTop + segment.offsetHeight + 4}px`
      return
    }
    const left = Math.min(segment.offsetLeft, figure.clientWidth - tip.offsetWidth - 8)
    tip.style.left = `${Math.max(8, left)}px`
    tip.style.top = `${list.offsetHeight - tip.offsetHeight - 12}px`
  }

  const show = (id) => {
    if (!tip) return
    active = id
    tip.innerHTML = tipHtml(items.get(id))
    placeTip(segments.get(id))
  }

  const hide = (id) => {
    if (!tip || active !== id) return
    active = null
    tip.hidden = true
  }

  const segmentFor = (item) => {
    const segment = document.createElement('li')
    segment.tabIndex = 0
    segment.innerHTML = `
      <span class="seg-down"></span>
      <span class="seg-up"></span>
      <span class="seg-label" aria-hidden="true"><span class="seg-name"></span><span class="seg-amount"></span></span>`
    segment.querySelector('.seg-name').textContent = item.name
    segment.addEventListener('pointerenter', () => show(item.id))
    segment.addEventListener('pointerleave', () => hide(item.id))
    segment.addEventListener('focus', () => show(item.id))
    segment.addEventListener('blur', () => hide(item.id))
    segments.set(item.id, segment)
    return segment
  }

  return (entries) => {
    const total = entries.reduce((sum, item) => sum + totalOf(item), 0)
    entries.forEach((item) => {
      items.set(item.id, item)
      const segment = segments.get(item.id) ?? segmentFor(item)
      const share = (totalOf(item) / total) * 100
      segment.style.setProperty('--share', share.toFixed(3))
      segment.style.setProperty('--down-share', String(item.down))
      segment.style.setProperty('--up-share', String(item.up))
      setText([segment.querySelector('.seg-amount')], formatBytes(totalOf(item)))
      fitLabel(segment)
      const label = describe(item)
      if (segment.getAttribute('aria-label') !== label) segment.setAttribute('aria-label', label)
    })
    const order = entries.map(({ id }) => id).join()
    if (list.dataset.order !== order) {
      list.dataset.order = order
      entries.forEach(({ id }) => list.append(segments.get(id)))
    }
    if (active) show(active)
    return total
  }
}

const renderApps = createShareBar($('[data-share="apps"]'))
const renderNetworks = createShareBar($('[data-share="networks"]'))

feed.subscribe((state) => {
  const total = renderApps(rankApps(state.apps))
  renderNetworks(state.networks.map((network) => ({
    ...network,
    rateDown: network.current ? state.rate.down : 0,
    rateUp: network.current ? state.rate.up : 0,
  })))
  setText($$('[data-share-total="apps"]'), formatBytes(total))
})

wireCommon()
mountMenuBar(feed)
