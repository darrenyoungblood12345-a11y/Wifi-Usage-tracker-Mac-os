import Foundation
import SQLite3
import Testing
@testable import WiFiTrackerCore

@Suite("Usage store")
struct UsageStoreTests {
  let store: UsageStore

  init() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "wifitracker-tests-\(UUID().uuidString)")
      .appending(path: "usage.sqlite")
    store = try UsageStore(url: url)
  }

  func at(_ seconds: TimeInterval) -> Date { Date(timeIntervalSince1970: seconds) }

  func record(_ seconds: TimeInterval, _ network: String = "Home", rx: UInt64, tx: UInt64 = 0) -> UsageRecord {
    UsageRecord(bucket: at(seconds), network: network, bytes: ByteCounters(received: rx, sent: tx))
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

  @Test("exports CSV with quoted network names")
  func csv() throws {
    try store.add([record(0, "Joe's \"Fast\", Wi-Fi", rx: 3, tx: 4)])
    let csv = try store.exportCSV()
    #expect(csv == "bucket_start,network,downloaded_bytes,uploaded_bytes\n1970-01-01T00:00:00Z,\"Joe's \"\"Fast\"\", Wi-Fi\",3,4\n")
  }

  @Test("clears all history, including per-app usage")
  func deleteAll() throws {
    try store.add([record(60, rx: 1)])
    try store.addAppUsage([appRecord(0, "curl", rx: 1)])
    try store.deleteAll()
    #expect(try store.allRecords().isEmpty)
    #expect(try store.appUsage(in: DateInterval(start: at(0), end: at(86_400))).isEmpty)
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
    var handle: OpaquePointer?
    #expect(sqlite3_open(url.path, &handle) == SQLITE_OK)
    #expect(sqlite3_exec(handle, "CREATE TABLE usage (bucket INTEGER NOT NULL, network TEXT NOT NULL, rx INTEGER NOT NULL DEFAULT 0, tx INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (bucket, network)) WITHOUT ROWID", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(handle)

    let store = try UsageStore(url: url)
    try store.addAppUsage([appRecord(0, "curl", rx: 1)])
    #expect(try store.appUsage(in: DateInterval(start: at(0), end: at(3_600))).count == 1)
  }
}
