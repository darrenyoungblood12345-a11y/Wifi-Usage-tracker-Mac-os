const REPO = 'darrenyoungblood12345-a11y/Wifi-Usage-tracker-Mac-os'
const DMG_NAME = 'WiFiTracker.dmg'

const IS_LOCAL = ['localhost', '127.0.0.1', ''].includes(location.hostname)
const DOWNLOAD_URL = IS_LOCAL
  ? `downloads/${DMG_NAME}`
  : `https://github.com/${REPO}/releases/latest/download/${DMG_NAME}`

const $ = (selector) => document.querySelector(selector)
const $$ = (selector) => [...document.querySelectorAll(selector)]

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

// Links

const wireLinks = () => {
  $$('[data-download]').forEach((link) => link.setAttribute('href', DOWNLOAD_URL))
  $$('[data-repo]').forEach((link) => link.setAttribute('href', `https://github.com/${REPO}`))
  $$('[data-releases]').forEach((link) => link.setAttribute('href', `https://github.com/${REPO}/releases`))
}

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
    if (version) $$('[data-release-version]').forEach((node) => { node.textContent = `Version ${version}` })
    if (asset?.size) $$('[data-release-size]').forEach((node) => { node.textContent = formatBytes(asset.size) })
  } catch {
    // Offline or rate-limited: keep the static text.
  }
}

const wireCopyButtons = () => {
  $$('[data-copy]').forEach((button) => {
    button.addEventListener('click', async () => {
      const text = document.getElementById(button.dataset.copy)?.textContent ?? ''
      try {
        await navigator.clipboard.writeText(text)
        button.textContent = 'Copied'
      } catch {
        button.textContent = 'Select & copy'
      }
      setTimeout(() => { button.textContent = 'Copy' }, 1600)
    })
  })
}

// Live demo: simulated traffic shaped like real use (idle, browsing, streaming, a big download, a call).

const SCENES = [
  { duration: [4, 8], down: [6e3, 40e3], up: [2e3, 12e3], jitter: 0.6 },
  { duration: [3, 5], down: [0.6e6, 2.8e6], up: [40e3, 160e3], jitter: 0.5 },
  { duration: [8, 13], down: [1.6e6, 2.4e6], up: [25e3, 60e3], jitter: 0.15 },
  { duration: [5, 9], down: [6e6, 8.5e6], up: [120e3, 260e3], jitter: 0.08 },
  { duration: [8, 12], down: [350e3, 500e3], up: [300e3, 450e3], jitter: 0.15 },
]

const between = ([low, high]) => low + Math.random() * (high - low)

const createTraffic = () => {
  let scene = SCENES[0]
  let remaining = 0
  let base = { down: 0, up: 0 }
  let last = { down: 20e3, up: 6e3 }

  const nextScene = () => {
    const isIdle = scene === SCENES[0]
    scene = isIdle ? SCENES[1 + Math.floor(Math.random() * (SCENES.length - 1))] : SCENES[0]
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
    return last
  }
}

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

const startDemo = () => {
  const svg = $('.spark')
  if (!svg) return

  const WIDTH = 300
  const HEIGHT = 90
  const WINDOW_SECONDS = 60
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches
  const nextSample = createTraffic()
  const nodes = Object.fromEntries($$('[data-demo]').map((node) => [node.dataset.demo, node]))
  const today = { down: 1.11e9, up: 0.128e9 }

  const now = Date.now()
  let samples = Array.from({ length: WINDOW_SECONDS + 2 }, (_, index) => ({
    time: now - (WINDOW_SECONDS + 1 - index) * 1000,
    ...nextSample(),
  }))
  let yMax = 1

  const updateText = () => {
    const { down, up } = samples.at(-1)
    nodes.down.textContent = formatRate(down)
    nodes.up.textContent = formatRate(up)
    nodes['menu-down'].textContent = formatRate(down)
    nodes['menu-up'].textContent = formatRate(up)
    nodes.today.textContent = formatBytes(today.down + today.up)
    nodes['today-down'].textContent = formatBytes(today.down)
    nodes['today-up'].textContent = formatBytes(today.up)
    nodes.clock.textContent = new Date().toLocaleString(undefined, { weekday: 'short', hour: 'numeric', minute: '2-digit' })
  }

  const draw = (time) => {
    const target = Math.max(...samples.map(({ down, up }) => Math.max(down, up))) * 1.15 || 1
    yMax = reduceMotion ? target : yMax + (target - yMax) * 0.08
    const x = (sampleTime) => WIDTH - ((time - sampleTime) / 1000 / WINDOW_SECONDS) * WIDTH
    const y = (value) => HEIGHT - 2 - (value / yMax) * (HEIGHT - 6)
    const series = (key) => samples.map((sample) => [x(sample.time), y(sample[key])])

    ;['download', 'upload'].forEach((name) => {
      const points = series(name === 'download' ? 'down' : 'up')
      const line = smoothPath(points, HEIGHT - 2)
      nodes[`line-${name}`].setAttribute('d', line)
      nodes[`area-${name}`].setAttribute('d', `${line} L${points.at(-1)[0].toFixed(1)},${HEIGHT} L${points[0][0].toFixed(1)},${HEIGHT} Z`)
    })
  }

  updateText()
  draw(samples.at(-1).time)
  if (reduceMotion) return

  setInterval(() => {
    const sample = { time: Date.now(), ...nextSample() }
    today.down += sample.down
    today.up += sample.up
    samples = [...samples.filter(({ time }) => time > sample.time - (WINDOW_SECONDS + 2) * 1000), sample]
    updateText()
  }, 1000)

  // Scroll continuously, lagging one second so the newest point slides in from the right edge.
  const frame = () => {
    draw(Date.now() - 1000)
    requestAnimationFrame(frame)
  }
  requestAnimationFrame(frame)
}

wireLinks()
wireCopyButtons()
startDemo()
loadReleaseInfo()
