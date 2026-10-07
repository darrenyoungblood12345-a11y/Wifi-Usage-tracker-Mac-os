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

mkdirSync(dirname(path), { recursive: true })
rmSync(path, { force: true })
const db = new DatabaseSync(path)
db.exec(`CREATE TABLE usage (
  bucket INTEGER NOT NULL, network TEXT NOT NULL,
  rx INTEGER NOT NULL DEFAULT 0, tx INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (bucket, network)
) WITHOUT ROWID`)
const insert = db.prepare('INSERT INTO usage (bucket, network, rx, tx) VALUES (?, ?, ?, ?)')
db.exec('BEGIN')
rows.forEach(({ bucket, network, rx, tx }) => insert.run(bucket, network, rx, tx))
db.exec('COMMIT')
db.close()

const totalGB = rows.reduce((sum, { rx, tx }) => sum + rx + tx, 0) / 1e9
console.log(`Seeded ${rows.length} hourly rows (${totalGB.toFixed(1)} GB) into ${path}`)
