import Foundation
import SQLite3
import Testing
import WiFiTrackerCore
@testable import WiFiTracker

private struct AppReadFailure: Error, CustomStringConvertible {
  var description: String { "The app history table is unavailable." }
}

// Free functions, so the reads (which run off the main actor) can use them too.
private func usage(_ id: String, _ bytes: UInt64) -> AppUsage {
  AppUsage(id: id, name: id, bytes: ByteCounters(received: bytes, sent: 0))
}

private func wifi(_ bytes: UInt64) -> ByteCounters {
  ByteCounters(received: bytes, sent: 0)
}

@Suite("App usage presentation")
@MainActor
struct AppUsageModelTests {
  @Test("read failures keep the last good snapshot and publish an error until a read succeeds")
  func readFailure() async {
    let model = AppUsageModel()
    let saved = [usage("curl", 100)]
    await model.load(.day) { (saved, wifi(120)) }
    #expect(model.loadError == nil)

    await model.load(.day) { throw AppReadFailure() }
    #expect(model.apps == saved)
    #expect(model.wifiTotal == wifi(120))
    #expect(model.loadError?.contains("table is unavailable") == true)
    // Usage that isn't saved yet keeps showing on top of the snapshot.
    let list = model.list(pendingApps: [usage("curl", 5)], pendingWifi: wifi(5))
    #expect(list.map(\.bytes.received) == [105, 20])

    await model.load(.day) { ([usage("curl", 130)], wifi(150)) }
    #expect(model.apps == [usage("curl", 130)])
    #expect(model.loadError == nil)
  }

  @Test("an unreadable app table doesn't turn saved app usage into Other traffic")
  func sqliteAppTableFailure() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "WiFiTracker-apps-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "usage.sqlite")
    let store = try UsageStore(url: url)
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    try store.add([UsageRecord(bucket: minuteBucket(for: now), network: "Home", bytes: wifi(120))])
    try store.addAppUsage([AppUsageRecord(bucket: hourBucket(for: now), app: "curl", name: "curl", bytes: wifi(100))])

    let model = AppUsageModel()
    await model.load(.day, from: store, now: now)
    #expect(model.list(pendingApps: [], pendingWifi: .zero).map(\.bytes.received) == [100, 20])

    // Only the app table fails; the Wi-Fi total is still readable.
    var db: OpaquePointer?
    #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
    #expect(sqlite3_exec(db, "DROP TABLE app_usage", nil, nil, nil) == SQLITE_OK)
    sqlite3_close(db)
    await model.load(.day, from: store, now: now)

    #expect(model.list(pendingApps: [], pendingWifi: .zero).map(\.bytes.received) == [100, 20])
    #expect(model.loadError?.contains("app_usage") == true)
  }

  @Test("a failed read for another range shows nothing saved rather than the previous range's rows")
  func rangeChange() async {
    let model = AppUsageModel()
    let saved = [usage("curl", 100)]
    await model.load(.day) { (saved, wifi(120)) }
    await model.load(.month) { throw AppReadFailure() }
    #expect(model.apps.isEmpty)
    #expect(model.wifiTotal == .zero)
    #expect(model.loadError != nil)

    await model.load(.day) { throw AppReadFailure() }
    #expect(model.apps == saved)
    #expect(model.wifiTotal == wifi(120))
  }

  @Test("clearing history drops the snapshots a later failed read would fall back to")
  func clearHistory() async {
    let model = AppUsageModel()
    await model.load(.day, epoch: 0) { ([usage("curl", 100)], wifi(120)) }
    await model.load(.day, epoch: 1) { throw AppReadFailure() }
    #expect(model.apps.isEmpty)
    #expect(model.wifiTotal == .zero)
    #expect(model.loadError != nil)
  }

  @Test("cancelled reads change neither the snapshot nor the error")
  func cancelledRead() async {
    let model = AppUsageModel()
    let saved = [usage("curl", 100)]
    await model.load(.day) { (saved, wifi(120)) }
    let cancelled = Task {
      await model.load(.day) {
        await Task.yield()
        withUnsafeCurrentTask { $0?.cancel() }
        throw AppReadFailure()
      }
    }
    await cancelled.value
    #expect(model.apps == saved)
    #expect(model.loadError == nil)
  }
}
