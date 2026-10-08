import Foundation
import SQLite3

public enum UsageStoreError: Error, CustomStringConvertible {
  case sqlite(String)

  public var description: String {
    switch self {
    case .sqlite(let message): "SQLite error: \(message)"
    }
  }
}

/// Usage totals for the dashboard's stat tiles.
public struct PeriodTotals: Equatable, Sendable {
  public var today: ByteCounters
  public var week: ByteCounters
  public var month: ByteCounters
  public var allTime: ByteCounters

  public init(today: ByteCounters = .zero, week: ByteCounters = .zero, month: ByteCounters = .zero, allTime: ByteCounters = .zero) {
    self.today = today
    self.week = week
    self.month = month
    self.allTime = allTime
  }

  public static let zero = PeriodTotals()

  public static func + (lhs: PeriodTotals, delta: ByteCounters) -> PeriodTotals {
    PeriodTotals(today: lhs.today + delta, week: lhs.week + delta, month: lhs.month + delta, allTime: lhs.allTime + delta)
  }
}

/// Per-minute usage history in SQLite, plus hourly usage per app.
///
/// Calls are synchronous and serialised by a lock so the app can flush on quit without awaiting;
/// heavier reads can be made from a background task.
public final class UsageStore: @unchecked Sendable {
  private let db: OpaquePointer
  private let lock = NSLock()

  /// `~/Library/Application Support/WiFiTracker/usage.sqlite`
  public static var defaultURL: URL {
    URL.applicationSupportDirectory
      .appending(path: "WiFiTracker", directoryHint: .isDirectory)
      .appending(path: "usage.sqlite")
  }

  public init(url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var handle: OpaquePointer?
    guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open \(url.path)"
      sqlite3_close(handle)
      throw UsageStoreError.sqlite(message)
    }
    db = handle
    try execute("PRAGMA journal_mode = WAL")
    try createUsageTable()
    try migrateUsageAttribution()
    try execute("""
      CREATE TABLE IF NOT EXISTS app_usage (
        bucket INTEGER NOT NULL,
        app    TEXT    NOT NULL,
        name   TEXT    NOT NULL,
        rx     INTEGER NOT NULL DEFAULT 0,
        tx     INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (bucket, app)
      ) WITHOUT ROWID
      """)
    try execute("""
      CREATE TABLE IF NOT EXISTS counter_checkpoint (
        id      INTEGER PRIMARY KEY CHECK (id = 1),
        payload TEXT NOT NULL
      )
      """)
  }

  deinit {
    sqlite3_close(db)
  }

  // MARK: Writes

  /// Adds records to whatever is already stored for the same bucket and network.
  public func add(_ records: [UsageRecord]) throws {
    try add(records, checkpoint: nil)
  }

  /// Commits usage and the counters it covers together, including a baseline with no new usage.
  public func add(_ records: [UsageRecord], checkpoint: CounterCheckpoint?) throws {
    guard !records.isEmpty || checkpoint != nil else { return }
    try locked {
      try transaction {
        try withStatement("""
          INSERT INTO usage (bucket, network, rx, tx, unattributed) VALUES (?, ?, ?, ?, ?)
          ON CONFLICT (bucket, network, unattributed) DO UPDATE SET rx = rx + excluded.rx, tx = tx + excluded.tx
          """) { statement in
          try records.forEach { record in
            sqlite3_bind_int64(statement, 1, seconds(record.bucket))
            sqlite3_bind_text(statement, 2, record.network, -1, sqliteTransient)
            sqlite3_bind_int64(statement, 3, Int64(clamping: record.bytes.received))
            sqlite3_bind_int64(statement, 4, Int64(clamping: record.bytes.sent))
            sqlite3_bind_int(statement, 5, record.isUnattributed ? 1 : 0)
            try step(statement)
            sqlite3_reset(statement)
          }
        }
        if let checkpoint {
          try writeCheckpoint(checkpoint)
        }
      }
    }
  }

  /// Adds per-app records to whatever is already stored for the same hour and app, keeping the newest name.
  public func addAppUsage(_ records: [AppUsageRecord]) throws {
    guard !records.isEmpty else { return }
    try locked {
      try transaction {
        try withStatement("""
          INSERT INTO app_usage (bucket, app, name, rx, tx) VALUES (?, ?, ?, ?, ?)
          ON CONFLICT (bucket, app) DO UPDATE SET name = excluded.name, rx = rx + excluded.rx, tx = tx + excluded.tx
          """) { statement in
          try records.forEach { record in
            sqlite3_bind_int64(statement, 1, seconds(record.bucket))
            sqlite3_bind_text(statement, 2, record.app, -1, sqliteTransient)
            sqlite3_bind_text(statement, 3, record.name, -1, sqliteTransient)
            sqlite3_bind_int64(statement, 4, Int64(clamping: record.bytes.received))
            sqlite3_bind_int64(statement, 5, Int64(clamping: record.bytes.sent))
            try step(statement)
            sqlite3_reset(statement)
          }
        }
      }
    }
  }

  /// Rolls minute buckets older than `cutoff` up into hour buckets to keep the database small.
  public func compact(olderThan cutoff: Date) throws {
    try locked {
      try transaction {
        try withStatement("""
          INSERT INTO usage (bucket, network, rx, tx, unattributed)
          SELECT (bucket / 3600) * 3600 AS hour, network, SUM(rx), SUM(tx), unattributed
          FROM usage WHERE bucket < ?1 AND bucket % 3600 != 0
          GROUP BY hour, network, unattributed
          ON CONFLICT (bucket, network, unattributed) DO UPDATE SET rx = rx + excluded.rx, tx = tx + excluded.tx
          """) { statement in
          sqlite3_bind_int64(statement, 1, seconds(cutoff))
          try step(statement)
        }
        try withStatement("DELETE FROM usage WHERE bucket < ?1 AND bucket % 3600 != 0") { statement in
          sqlite3_bind_int64(statement, 1, seconds(cutoff))
          try step(statement)
        }
      }
    }
  }

  /// Clears history and saves a new counter baseline so cleared bytes cannot be recovered on restart.
  public func deleteAll(checkpoint: CounterCheckpoint? = nil) throws {
    try locked {
      try transaction {
        try execute("DELETE FROM usage")
        try execute("DELETE FROM app_usage")
        try execute("DELETE FROM counter_checkpoint")
        if let checkpoint {
          try writeCheckpoint(checkpoint)
        }
      }
    }
  }

  // MARK: Reads

  public func checkpoint() throws -> CounterCheckpoint? {
    try locked {
      let payload = try withStatement("SELECT payload FROM counter_checkpoint WHERE id = 1") { statement in
        try rows(statement) { row in
          sqlite3_column_text(row, 0).map { String(cString: $0) } ?? ""
        }.first
      }
      guard let payload else { return nil }
      return try JSONDecoder().decode(CounterCheckpoint.self, from: Data(payload.utf8))
    }
  }

  public func records(in interval: DateInterval) throws -> [UsageRecord] {
    try locked {
      try withStatement("SELECT bucket, network, rx, tx, unattributed FROM usage WHERE bucket >= ?1 AND bucket < ?2 ORDER BY bucket, network, unattributed") { statement in
        sqlite3_bind_int64(statement, 1, seconds(interval.start))
        sqlite3_bind_int64(statement, 2, seconds(interval.end))
        return try rows(statement, map: record(from:))
      }
    }
  }

  public func allRecords() throws -> [UsageRecord] {
    try locked {
      try withStatement("SELECT bucket, network, rx, tx, unattributed FROM usage ORDER BY bucket, network, unattributed") { statement in
        try rows(statement, map: record(from:))
      }
    }
  }

  /// Total bytes in buckets starting at or after `start` (or ever, when `nil`).
  public func total(since start: Date?) throws -> ByteCounters {
    try locked {
      try withStatement("SELECT COALESCE(SUM(rx), 0), COALESCE(SUM(tx), 0) FROM usage WHERE bucket >= ?1") { statement in
        sqlite3_bind_int64(statement, 1, start.map(seconds) ?? Int64.min)
        return try rows(statement) { row in
          ByteCounters(received: UInt64(clamping: sqlite3_column_int64(row, 0)), sent: UInt64(clamping: sqlite3_column_int64(row, 1)))
        }.first ?? .zero
      }
    }
  }

  /// Usage per app in hours starting within `interval`, largest first. Each app keeps its most recent name.
  public func appUsage(in interval: DateInterval) throws -> [AppUsage] {
    try locked {
      // A bare column next to MAX() takes its value from the row holding the maximum, i.e. the newest name.
      try withStatement("""
        SELECT app, name, SUM(rx), SUM(tx), MAX(bucket) FROM app_usage
        WHERE bucket >= ?1 AND bucket < ?2
        GROUP BY app
        ORDER BY SUM(rx) + SUM(tx) DESC, name
        """) { statement in
        sqlite3_bind_int64(statement, 1, seconds(interval.start))
        sqlite3_bind_int64(statement, 2, seconds(interval.end))
        return try rows(statement) { row in
          AppUsage(
            id: sqlite3_column_text(row, 0).map { String(cString: $0) } ?? "",
            name: sqlite3_column_text(row, 1).map { String(cString: $0) } ?? "",
            bytes: ByteCounters(
              received: UInt64(clamping: sqlite3_column_int64(row, 2)),
              sent: UInt64(clamping: sqlite3_column_int64(row, 3))
            )
          )
        }
      }
    }
  }

  public func periodTotals(now: Date = .now, calendar: Calendar = .current) throws -> PeriodTotals {
    let start = { (component: Calendar.Component) in calendar.dateInterval(of: component, for: now)?.start }
    return PeriodTotals(
      today: try total(since: start(.day)),
      week: try total(since: start(.weekOfYear)),
      month: try total(since: start(.month)),
      allTime: try total(since: nil)
    )
  }

  /// CSV of every stored bucket, oldest first.
  public func exportCSV() throws -> String {
    let formatter = ISO8601DateFormatter()
    let header = "bucket_start,network,downloaded_bytes,uploaded_bytes,unattributed"
    let lines = try allRecords().map { record in
      [formatter.string(from: record.bucket), csvField(record.network), String(record.bytes.received), String(record.bytes.sent), record.isUnattributed ? "1" : "0"]
        .joined(separator: ",")
    }
    return ([header] + lines).joined(separator: "\n") + "\n"
  }

  // MARK: SQLite helpers

  private func createUsageTable() throws {
    try execute("""
      CREATE TABLE IF NOT EXISTS usage (
        bucket       INTEGER NOT NULL,
        network      TEXT    NOT NULL,
        rx           INTEGER NOT NULL DEFAULT 0,
        tx           INTEGER NOT NULL DEFAULT 0,
        unattributed INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (bucket, network, unattributed)
      ) WITHOUT ROWID
      """)
  }

  private func migrateUsageAttribution() throws {
    let columns = try withStatement("PRAGMA table_info(usage)") { statement in
      try rows(statement) { row in
        sqlite3_column_text(row, 1).map { String(cString: $0) } ?? ""
      }
    }
    guard !columns.contains("unattributed") else { return }
    try transaction {
      try execute("ALTER TABLE usage RENAME TO usage_legacy")
      try createUsageTable()
      // Legacy fallback labels cannot be distinguished from real SSIDs; preserve them verbatim.
      try execute("INSERT INTO usage (bucket, network, rx, tx, unattributed) SELECT bucket, network, rx, tx, 0 FROM usage_legacy")
      try execute("DROP TABLE usage_legacy")
    }
  }

  private func writeCheckpoint(_ checkpoint: CounterCheckpoint) throws {
    let payload = String(decoding: try JSONEncoder().encode(checkpoint), as: UTF8.self)
    try withStatement("""
      INSERT INTO counter_checkpoint (id, payload) VALUES (1, ?1)
      ON CONFLICT (id) DO UPDATE SET payload = excluded.payload
      """) { statement in
      sqlite3_bind_text(statement, 1, payload, -1, sqliteTransient)
      try step(statement)
    }
  }

  private func locked<T>(_ body: () throws -> T) rethrows -> T {
    lock.lock()
    defer { lock.unlock() }
    return try body()
  }

  private func execute(_ sql: String) throws {
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw lastError() }
  }

  private func transaction(_ body: () throws -> Void) throws {
    try execute("BEGIN")
    do {
      try body()
      try execute("COMMIT")
    } catch {
      try? execute("ROLLBACK")
      throw error
    }
  }

  private func withStatement<T>(_ sql: String, _ body: (OpaquePointer) throws -> T) throws -> T {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw lastError() }
    defer { sqlite3_finalize(statement) }
    return try body(statement)
  }

  private func step(_ statement: OpaquePointer) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
  }

  private func rows<T>(_ statement: OpaquePointer, map: (OpaquePointer) -> T) throws -> [T] {
    var result: [T] = []
    while true {
      switch sqlite3_step(statement) {
      case SQLITE_ROW: result.append(map(statement))
      case SQLITE_DONE: return result
      default: throw lastError()
      }
    }
  }

  private func record(from row: OpaquePointer) -> UsageRecord {
    UsageRecord(
      bucket: Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(row, 0))),
      network: sqlite3_column_text(row, 1).map { String(cString: $0) } ?? "",
      bytes: ByteCounters(
        received: UInt64(clamping: sqlite3_column_int64(row, 2)),
        sent: UInt64(clamping: sqlite3_column_int64(row, 3))
      ),
      isUnattributed: sqlite3_column_int(row, 4) != 0
    )
  }

  private func lastError() -> UsageStoreError {
    .sqlite(String(cString: sqlite3_errmsg(db)))
  }
}

/// Start of the minute containing `date`, which is the granularity records are stored at.
public func minuteBucket(for date: Date) -> Date {
  Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 60).rounded(.down) * 60)
}

private func seconds(_ date: Date) -> Int64 {
  Int64(date.timeIntervalSince1970.rounded(.down))
}

private func csvField(_ value: String) -> String {
  guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return value }
  return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
}

/// Tells SQLite to copy bound strings, since Swift's temporary C strings don't outlive the call.
private var sqliteTransient: sqlite3_destructor_type {
  unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
