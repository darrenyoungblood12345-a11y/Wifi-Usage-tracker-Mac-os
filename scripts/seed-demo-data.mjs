// Fills a separate SQLite database with a year of plausible sample usage, for website screenshots.
// Never touches your real history. Usage: node scripts/seed-demo-data.mjs <path/to/demo.sqlite>
import { DatabaseSync } from 'node:sqlite'
import { mkdirSync, rmSync } from 'node:fs'
import { dirname } from 'node:path'

const path = process.argv[2]
if (!path) {
  console.error('Usage: node scripts/seed-demo-data.mjs <path/to/demo.sqlite>')
  process.exit(1)
}

const MB = 1_000_000
const DAYS = 365

// Deterministic pseudo-random numbers so screenshots are reproducible.
const random = (() => {
  let seed = 42
  return () => {
    seed = (seed * 1_664_525 + 1_013_904_223) % 2 ** 32
    return seed / 2 ** 32
  }
})()

// Where the laptop is at a given local hour: office on weekdays, café now and then, home otherwise.
const networkAt = (date) => {
  const hour = date.getHours()
  const weekday = date.getDay() >= 1 && date.getDay() <= 5
  if (weekday && hour >= 9 && hour < 17) return date.getDate() % 6 === 0 ? 'Corner Café' : 'Office'
  return 'Home Wi-Fi'
}

// Megabytes downloaded in an hour: quiet overnight, busy evenings, heavier weekends.
const downloadAt = (date) => {
  const hour = date.getHours()
  const weekend = date.getDay() === 0 || date.getDay() === 6
  const base = hour < 7 ? 8 : hour < 9 ? 60 : hour < 17 ? 130 : hour < 23 ? 260 : 45
  return base * (weekend ? 1.4 : 1) * (0.45 + random() * 1.1) * MB
}

const HOUR = 3_600_000
const thisHour = Math.floor(Date.now() / HOUR) * HOUR

// Step back in absolute hours (not local clock hours) so DST changes can't produce duplicate buckets.
const rows = Array.from({ length: DAYS * 24 }, (_, index) => {
  const date = new Date(thisHour - index * HOUR)
  const rx = Math.round(downloadAt(date))
  const tx = Math.round(rx * (0.08 + random() * 0.14))
  return { bucket: Math.floor(date.getTime() / 1000), network: networkAt(date), rx, tx }
})

// Each hour's traffic split across apps (shares of download, upload), jittered per hour. The shares add
// up to a little under 1, like real data: the rest (packet headers etc.) shows up as "Other traffic".
const APPS = [
  ['com.apple.Safari', 'Safari', 0.3, 0.22],
  ['com.google.Chrome', 'Google Chrome', 0.18, 0.16],
  ['com.apple.Music', 'Music', 0.13, 0.02],
  ['com.apple.TV', 'TV', 0.12, 0.01],
  ['com.apple.FaceTime', 'FaceTime', 0.07, 0.32],
  ['com.apple.AppStore', 'App Store', 0.05, 0.005],
  ['com.apple.mail', 'Mail', 0.04, 0.06],
  ['com.apple.Photos', 'Photos', 0.03, 0.12],
  ['nsurlsessiond', 'nsurlsessiond', 0.02, 0.02],
  ['softwareupdated', 'softwareupdated', 0.02, 0.002],
  ['mDNSResponder', 'mDNSResponder', 0.004, 0.01],
]
const ATTRIBUTED = 0.95

const appRows = rows.flatMap(({ bucket, rx, tx }) => {
  const jittered = APPS.map(([app, name, down, up]) => {
    const jitter = 0.6 + random() * 0.8
    return { app, name, down: down * jitter, up: up * jitter }
  })
  const downSum = jittered.reduce((sum, { down }) => sum + down, 0)
  const upSum = jittered.reduce((sum, { up }) => sum + up, 0)
  return jittered.map(({ app, name, down, up }) => ({
    bucket,
    app,
    name,
    rx: Math.round((rx * ATTRIBUTED * down) / downSum),
    tx: Math.round((tx * ATTRIBUTED * up) / upSum),
  }))
})

mkdirSync(dirname(path), { recursive: true })
rmSync(path, { force: true })
const db = new DatabaseSync(path)
db.exec(`CREATE TABLE usage (
  bucket INTEGER NOT NULL, network TEXT NOT NULL,
  rx INTEGER NOT NULL DEFAULT 0, tx INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (bucket, network)
) WITHOUT ROWID`)
const insert = db.prepare('INSERT INTO usage (bucket, network, rx, tx) VALUES (?, ?, ?, ?)')
db.exec(`CREATE TABLE app_usage (
  bucket INTEGER NOT NULL, app TEXT NOT NULL, name TEXT NOT NULL,
  rx INTEGER NOT NULL DEFAULT 0, tx INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (bucket, app)
) WITHOUT ROWID`)
const insertApp = db.prepare('INSERT INTO app_usage (bucket, app, name, rx, tx) VALUES (?, ?, ?, ?, ?)')
db.exec('BEGIN')
rows.forEach(({ bucket, network, rx, tx }) => insert.run(bucket, network, rx, tx))
appRows.forEach(({ bucket, app, name, rx, tx }) => insertApp.run(bucket, app, name, rx, tx))
db.exec('COMMIT')
db.close()

const totalGB = rows.reduce((sum, { rx, tx }) => sum + rx + tx, 0) / 1e9
console.log(`Seeded ${rows.length} hourly rows (${totalGB.toFixed(1)} GB) and ${appRows.length} app rows into ${path}`)
