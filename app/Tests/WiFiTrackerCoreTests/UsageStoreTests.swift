import Foundation
import SQLite3
import Testing
@testable import WiFiTrackerCore

@Suite("Usage store")
struct UsageStoreTests {
  let store: UsageStore
  let databaseURL: URL

  init() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "wifitracker-tests-\(UUID().uuidString)")
      .appending(path: "usage.sqlite")
    databaseURL = url
    store = try UsageStore(url: url)
  }

  func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

  func record(_ seconds: TimeInterval, _ network: String = "Home", rx: UInt64, tx: UInt64 = 0, isUnattributed: Bool = false) -> UsageRecord {
    UsageRecord(bucket: at(seconds), network: network, bytes: ByteCounters(received: rx, sent: tx), isUnattributed: isUnattributed)
  }

  @Test("adds to an existing bucket instead of replacing it")
  func upsertAccumulates() throws {
    try store.add([record(3_600, rx: 100, tx: 10)])
    try store.add([record(3_600, rx: 50, tx: 5), record(3_600, "Cafe", rx: 1)])
    let records = try store.allRecords()
    #expect(records.count == 2)
    #expect(records.first { $0.network == "Home" }?.bytes == ByteCounters(received: 150, sent: 15))
  }

  @Test("filters records to a half-open interval")
  func rangeQuery() throws {
    try store.add([record(60, rx: 1), record(120, rx: 2), record(180, rx: 4)])
    let records = try store.records(in: DateInterval(start: at(60), end: at(180)))
    #expect(records.map(\.bytes.received) == [1, 2])
    #expect(try store.total(since: at(120)) == ByteCounters(received: 6, sent: 0))
    #expect(try store.total(since: nil) == ByteCounters(received: 7, sent: 0))
  }

  @Test("compacts old minutes into hours without losing bytes")
  func compaction() throws {
    try store.add([
      record(7_200, rx: 1),             // 02:00 minute (already on the hour)
      record(7_260, rx: 2, tx: 1),      // 02:01
      record(10_740, rx: 4),            // 02:59
      record(10_740, "Cafe", rx: 8),    // 02:59, other network
      record(10_800, rx: 16),           // 03:00, newer than cutoff
      record(10_860, rx: 32),           // 03:01, newer than cutoff
    ])
    try store.compact(olderThan: at(10_800))
    let records = try store.allRecords()
    #expect(records.map { "\(Int($0.bucket.timeIntervalSince1970)) \($0.network) \($0.bytes.received)" } == [
      "7200 Cafe 8",
      "7200 Home 7",
      "10800 Home 16",
      "10860 Home 32",
    ])
    #expect(try store.total(since: nil) == ByteCounters(received: 63, sent: 1))
  }

  @Test("keeps unidentified usage separate from a real network named Wi-Fi, including after compaction")
  func attributionSurvivesCompaction() throws {
    try store.add([
      record(3_600, "Wi-Fi", rx: 1),
      record(3_660, "Wi-Fi", rx: 2),
      record(3_600, "Wi-Fi", rx: 4, isUnattributed: true),
      record(3_660, "Wi-Fi", rx: 8, isUnattributed: true),
    ])
    let interval = DateInterval(start: at(3_600), end: at(7_200))
    #expect(try store.records(in: interval).filter(\.isUnattributed).map(\.bytes.received) == [4, 8])
    try store.compact(olderThan: at(7_200))
    #expect(try store.allRecords() == [
      record(3_600, "Wi-Fi", rx: 3),
      record(3_600, "Wi-Fi", rx: 12, isUnattributed: true),
    ])
    #expect(try store.total(since: nil) == ByteCounters(received: 15, sent: 0))
    try store.compact(olderThan: at(7_200))
    #expect(try store.total(since: nil) == ByteCounters(received: 15, sent: 0))
  }

  @Test("exports CSV with quoted network names")
  func csv() throws {
    try store.add([record(0, "Joe's \"Fast\", Wi-Fi", rx: 3, tx: 4)])
    let csv = try store.exportCSV()
    #expect(csv == "bucket_start,network,downloaded_bytes,uploaded_bytes,unattributed\n1970-01-01T00:00:00Z,\"Joe's \"\"Fast\"\", Wi-Fi\",3,4,0\n")
  }

  @Test("exports named and unidentified records with distinguishable attribution")
  func csvAttribution() throws {
    try store.add([
      record(0, "Wi-Fi", rx: 3),
      record(0, "Wi-Fi", rx: 4, isUnattributed: true),
    ])
    #expect(try store.exportCSV() == "bucket_start,network,downloaded_bytes,uploaded_bytes,unattributed\n1970-01-01T00:00:00Z,Wi-Fi,3,0,0\n1970-01-01T00:00:00Z,Wi-Fi,4,0,1\n")
  }

  @Test("clears all history, including per-app usage")
  func deleteAll() throws {
    try store.add([record(60, rx: 1)], checkpoint: checkpoint(rx: 100))
    try store.addAppUsage([appRecord(0, "curl", rx: 1)])
    try store.deleteAll()
    #expect(try store.allRecords().isEmpty)
    #expect(try store.appUsage(in: DateInterval(start: at(0), end: at(86_400))).isEmpty)
    #expect(try store.checkpoint() == nil)
  }

  @Test("persists counter checkpoints across reopening, including checkpoints without usage")
  func checkpointRoundtrip() throws {
    #expect(try store.checkpoint() == nil)
    let first = checkpoint(rx: 100, tx: 20)
    try store.add([record(60, rx: 2, tx: 1)], checkpoint: first)
    let reopened = try UsageStore(url: databaseURL)
    #expect(try reopened.checkpoint() == first)
    #expect(try reopened.total(since: nil) == ByteCounters(received: 2, sent: 1))
    let second = checkpoint(rx: 120, tx: 21, date: 180)
    try reopened.add([], checkpoint: second)
    #expect(try store.checkpoint() == second)
    try store.add([record(120, rx: 1)])
    #expect(try store.checkpoint() == second)
  }

  @Test("an unchanged counter reading after reopening does not count committed usage twice")
  func unchangedCounterRestart() throws {
    let baseline = checkpoint(rx: 100, tx: 20)
    try store.add([record(60, rx: 100, tx: 20)], checkpoint: baseline)
    let reopened = try UsageStore(url: databaseURL)
    let saved = try #require(try reopened.checkpoint())
    var accounting = NetworkAccounting()
    let resumed = NetworkSample(
      date: at(180), uptime: 180, interface: "en0", counters: baseline.counters, network: .named("Home")
    )
    let resumedDelta = accounting.restore(saved, bootTime: at(0), sample: resumed)
    #expect(resumedDelta == nil)
    try reopened.add([], checkpoint: accounting.checkpoint(bootTime: at(0)))
    #expect(try reopened.allRecords() == [record(60, rx: 100, tx: 20)])
    let next = NetworkSample(
      date: at(181), uptime: 181, interface: "en0", counters: ByteCounters(received: 103, sent: 21), network: .named("Home")
    )
    let nextDelta = accounting.update(next)
    let delta = try #require(nextDelta)
    try reopened.add([record(180, rx: delta.bytes.received, tx: delta.bytes.sent)], checkpoint: accounting.checkpoint(bootTime: at(0)))
    #expect(try reopened.total(since: nil) == ByteCounters(received: 103, sent: 21))
  }

  @Test("clearing history replaces the restart baseline atomically")
  func clearWithCheckpoint() throws {
    try store.add([record(60, rx: 1)], checkpoint: checkpoint(rx: 100))
    try store.addAppUsage([appRecord(0, "curl", rx: 1)])
    let baseline = checkpoint(rx: 200, date: 180)
    try store.deleteAll(checkpoint: baseline)
    let reopened = try UsageStore(url: databaseURL)
    #expect(try reopened.checkpoint() == baseline)
    #expect(try reopened.allRecords().isEmpty)
    #expect(try reopened.appUsage(in: DateInterval(start: at(0), end: at(3_600))).isEmpty)
    var accounting = NetworkAccounting()
    let resumed = NetworkSample(
      date: at(240), uptime: 240, interface: "en0", counters: baseline.counters, network: .named("Home")
    )
    let saved = try #require(try reopened.checkpoint())
    let resumedDelta = accounting.restore(saved, bootTime: at(0), sample: resumed)
    #expect(resumedDelta == nil)
  }

  @Test("rolls back usage when saving its checkpoint fails, then permits a safe retry")
  func checkpointFailureRollsBackUsage() throws {
    let baseline = checkpoint(rx: 100)
    try store.add([record(60, rx: 1)], checkpoint: baseline)
    try executeFixtureSQL("""
      CREATE TRIGGER reject_checkpoint BEFORE UPDATE ON counter_checkpoint
      BEGIN SELECT RAISE(ABORT, 'checkpoint fixture failure'); END
      """, at: databaseURL)
    #expect(throws: UsageStoreError.self) {
      try store.add([record(60, rx: 2), record(120, rx: 4)], checkpoint: checkpoint(rx: 106))
    }
    #expect(try store.allRecords() == [record(60, rx: 1)])
    #expect(try store.checkpoint() == baseline)
    try executeFixtureSQL("DROP TRIGGER reject_checkpoint", at: databaseURL)
    try store.add([record(60, rx: 2), record(120, rx: 4)], checkpoint: checkpoint(rx: 106))
    #expect(try store.total(since: nil) == ByteCounters(received: 7, sent: 0))
    #expect(try store.checkpoint() == checkpoint(rx: 106))
  }

  @Test("rolls back history clearing when saving the replacement baseline fails")
  func clearFailureRollsBackHistory() throws {
    let baseline = checkpoint(rx: 100)
    try store.add([record(60, rx: 1)], checkpoint: baseline)
    try store.addAppUsage([appRecord(0, "curl", rx: 1)])
    try executeFixtureSQL("""
      CREATE TRIGGER reject_checkpoint BEFORE INSERT ON counter_checkpoint
      BEGIN SELECT RAISE(ABORT, 'checkpoint fixture failure'); END
      """, at: databaseURL)
    #expect(throws: UsageStoreError.self) {
      try store.deleteAll(checkpoint: checkpoint(rx: 200))
    }
    #expect(try store.allRecords() == [record(60, rx: 1)])
    #expect(try store.checkpoint() == baseline)
    #expect(try store.appUsage(in: DateInterval(start: at(0), end: at(3_600))) == [
      AppUsage(id: "curl", name: "curl", bytes: ByteCounters(received: 1, sent: 0)),
    ])
  }

  func appRecord(_ seconds: TimeInterval, _ app: String, name: String? = nil, rx: UInt64, tx: UInt64 = 0) -> AppUsageRecord {
    AppUsageRecord(bucket: at(seconds), app: app, name: name ?? app, bytes: ByteCounters(received: rx, sent: tx))
  }

  @Test("adds app usage to the same hour and sums it per app, largest first, with the newest name")
  func appUsage() throws {
    try store.addAppUsage([
      appRecord(0, "com.google.Chrome", name: "Chrome", rx: 100, tx: 10),
      appRecord(0, "curl", rx: 5),
    ])
    try store.addAppUsage([
      appRecord(0, "com.google.Chrome", name: "Chrome", rx: 50),
      appRecord(3_600, "com.google.Chrome", name: "Google Chrome", rx: 1),
      appRecord(3_600, "curl", rx: 500),
      appRecord(7_200, "curl", rx: 9_999), // outside the interval
    ])
    let apps = try store.appUsage(in: DateInterval(start: at(0), end: at(7_200)))
    #expect(apps == [
      AppUsage(id: "curl", name: "curl", bytes: ByteCounters(received: 505, sent: 0)),
      AppUsage(id: "com.google.Chrome", name: "Google Chrome", bytes: ByteCounters(received: 151, sent: 10)),
    ])
  }

  @Test("adds the app usage table to a database created before it existed")
  func migratesOldDatabase() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "wifitracker-tests-\(UUID().uuidString)")
      .appending(path: "usage.sqlite")
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try executeFixtureSQL("""
      CREATE TABLE usage (bucket INTEGER NOT NULL, network TEXT NOT NULL, rx INTEGER NOT NULL DEFAULT 0, tx INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (bucket, network)) WITHOUT ROWID;
      INSERT INTO usage (bucket, network, rx, tx) VALUES
        (60, 'Wi-Fi', 2, 3),
        (120, 'Unknown Network', 5, 7),
        (180, 'Cafe, "Fast"', 11, 13);
      """, at: url)

    let store = try UsageStore(url: url)
    let legacy = [
      record(60, "Wi-Fi", rx: 2, tx: 3),
      record(120, "Unknown Network", rx: 5, tx: 7),
      record(180, "Cafe, \"Fast\"", rx: 11, tx: 13),
    ]
    #expect(try store.allRecords() == legacy)
    #expect(try store.checkpoint() == nil)
    try store.add([record(60, "Wi-Fi", rx: 17, isUnattributed: true)])
    #expect(try store.allRecords().count == 4)
    #expect(try store.allRecords().filter { !$0.isUnattributed } == legacy)
    try store.addAppUsage([appRecord(0, "curl", rx: 1)])
    #expect(try store.appUsage(in: DateInterval(start: at(0), end: at(3_600))).count == 1)
    let reopened = try UsageStore(url: url)
    #expect(try reopened.allRecords() == store.allRecords())
  }

  func checkpoint(rx: UInt64, tx: UInt64 = 0, date: TimeInterval = 120) -> CounterCheckpoint {
    CounterCheckpoint(bootTime: at(0), interface: "en0", counters: ByteCounters(received: rx, sent: tx), date: at(date))
  }

  func executeFixtureSQL(_ sql: String, at url: URL) throws {
    var handle: OpaquePointer?
    guard sqlite3_open(url.path, &handle) == SQLITE_OK, let handle else {
      let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "cannot open test database"
      sqlite3_close(handle)
      throw UsageStoreError.sqlite(message)
    }
    defer { sqlite3_close(handle) }
    guard sqlite3_exec(handle, sql, nil, nil, nil) == SQLITE_OK else {
      throw UsageStoreError.sqlite(String(cString: sqlite3_errmsg(handle)))
    }
  }
}
