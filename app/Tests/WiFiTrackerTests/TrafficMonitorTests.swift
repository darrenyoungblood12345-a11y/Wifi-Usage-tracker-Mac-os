import CoreLocation
import Foundation
import SQLite3
import Testing
import WiFiTrackerCore
@testable import WiFiTracker

/// Stands in for `nettop`: returns the output it was last given, or holds one call open until `finish`.
private actor NettopStub {
  private var output = ""
  private var holdsNext = false
  private var held: CheckedContinuation<String, Never>?
  private var heldWaiters: [CheckedContinuation<Void, Never>] = []

  /// One socket of a process that doesn't exist, so it is listed under its `nettop` name.
  static func output(received: UInt64) -> String {
    "curl.\(Int32.max),\(received),0,\ntcp4 10.0.0.2:5000<->1.1.1.1:443,\(received),0,\n"
  }

  func set(received: UInt64) {
    output = Self.output(received: received)
  }

  func holdNext() {
    holdsNext = true
  }

  func snapshot() async -> String {
    guard holdsNext else { return output }
    holdsNext = false
    heldWaiters.forEach { $0.resume() }
    heldWaiters = []
    return await withCheckedContinuation { held = $0 }
  }

  func waitUntilHeld() async {
    guard held == nil else { return }
    await withCheckedContinuation { heldWaiters.append($0) }
  }

  func finish(received: UInt64) {
    held?.resume(returning: Self.output(received: received))
    held = nil
  }
}

@Suite("Traffic monitor integration")
@MainActor
struct TrafficMonitorTests {
  @Test("publishes network usage before its first minute save")
  func livePending() throws {
    let fixture = try Fixture()
    fixture.monitor.tick()
    fixture.advance(received: 50, sent: 5)
    fixture.monitor.tick()
    #expect(fixture.monitor.pendingRecords.first?.identity == .named("Home"))
    #expect(totalUsage(fixture.monitor.pendingRecords) == ByteCounters(received: 50, sent: 5))
    #expect(try fixture.monitor.store?.allRecords().isEmpty == true)
    #expect(fixture.monitor.totals.today == ByteCounters(received: 50, sent: 5))
  }

  @Test("switching networks preserves bytes without charging the mixed sample to the new network")
  func switchNetwork() throws {
    let fixture = try Fixture()
    fixture.monitor.tick()
    fixture.advance(received: 50)
    fixture.monitor.tick()
    fixture.state.snapshot.ssid = "Cafe"
    fixture.advance(received: 20)
    fixture.monitor.tick()
    fixture.advance(received: 30)
    fixture.monitor.tick()
    let networks = usageByNetwork(fixture.monitor.pendingRecords)
    #expect(networks.first { $0.id == .named("Home") }?.bytes.received == 50)
    #expect(networks.first { $0.id == .named("Cafe") }?.bytes.received == 30)
    #expect(networks.first { $0.isUnattributed }?.bytes.received == 20)
    #expect(totalUsage(fixture.monitor.pendingRecords).received == 100)
  }

  @Test("a missing counter reading still flushes buffered traffic when due")
  func failedReadFlushes() throws {
    let fixture = try Fixture()
    fixture.monitor.tick()
    fixture.advance(received: 50)
    fixture.monitor.tick()
    fixture.state.counters = nil
    fixture.state.uptime = 60
    fixture.monitor.tick()
    #expect(fixture.monitor.pendingRecords.isEmpty)
    #expect(try fixture.monitor.store?.total(since: nil) == ByteCounters(received: 50, sent: 0))
    #expect(try fixture.monitor.store?.checkpoint()?.counters.received == 150)
  }

  @Test("automatic saves checkpoint the same current counters as the saved bytes")
  func automaticCheckpoint() throws {
    let fixture = try Fixture()
    fixture.monitor.tick()
    for _ in 0..<60 {
      fixture.advance(received: 10, sent: 1)
      fixture.monitor.tick()
    }
    let savedCheckpoint = try fixture.monitor.store?.checkpoint()
    let checkpoint = try #require(savedCheckpoint)
    #expect(checkpoint.counters == ByteCounters(received: 700, sent: 70))
    let restarted = fixture.makeMonitor()
    restarted.tick()
    #expect(restarted.pendingRecords.isEmpty)
    #expect(try restarted.store?.total(since: nil) == ByteCounters(received: 600, sent: 60))
  }

  @Test("a failed transaction preserves pending traffic and the previously durable checkpoint")
  func failedSaveAndRetry() throws {
    let fixture = try Fixture()
    fixture.monitor.tick()
    fixture.monitor.flush()
    try fixture.sql("CREATE TRIGGER fail_usage BEFORE INSERT ON usage BEGIN SELECT RAISE(ABORT, 'test failure'); END")
    fixture.advance(received: 50)
    fixture.monitor.tick()
    let revision = fixture.monitor.historyRevision
    fixture.monitor.flush()
    #expect(fixture.monitor.storeError != nil)
    #expect(totalUsage(fixture.monitor.pendingRecords).received == 50)
    #expect(fixture.monitor.historyRevision == revision)
    #expect(try fixture.monitor.store?.checkpoint()?.counters.received == 100)
    try fixture.sql("DROP TRIGGER fail_usage")
    fixture.monitor.flush()
    #expect(fixture.monitor.storeError == nil)
    #expect(fixture.monitor.pendingRecords.isEmpty)
    #expect(try fixture.monitor.store?.total(since: nil).received == 50)
    #expect(try fixture.monitor.store?.checkpoint()?.counters.received == 150)
  }

  @Test("clear history saves a fresh boundary and resets pending and session commits")
  func clearBaseline() throws {
    let fixture = try Fixture()
    fixture.monitor.tick()
    fixture.advance(received: 50)
    fixture.monitor.tick()
    fixture.monitor.flush()
    fixture.advance(received: 20)
    try fixture.monitor.clearHistory()
    #expect(fixture.monitor.historyEpoch == 1)
    #expect(fixture.monitor.pendingRecords.isEmpty)
    #expect(fixture.monitor.committedRecords.isEmpty)
    let restarted = fixture.makeMonitor()
    restarted.tick()
    #expect(restarted.pendingRecords.isEmpty)
    #expect(try restarted.store?.total(since: nil) == .zero)
    fixture.advance(received: 10)
    restarted.tick()
    #expect(totalUsage(restarted.pendingRecords).received == 10)
  }

  @Test("clear history restarts per-app accounting from a fresh socket baseline")
  func clearResetsAppBoundary() async throws {
    let fixture = try Fixture()
    let nettop = NettopStub()
    let apps = AppTrafficMonitor(snapshot: { await nettop.snapshot() })
    let monitor = fixture.makeMonitor(apps: apps)
    monitor.tick()
    await nettop.set(received: 1_000)
    await apps.sample()
    await nettop.set(received: 1_500)
    await apps.sample()
    #expect(apps.pendingUsage.map(\.bytes.received) == [500])

    // The socket moves another 300 bytes before the clear, which no sample has seen yet.
    try monitor.clearHistory()
    #expect(apps.pendingUsage.isEmpty)
    #expect(apps.rates.isEmpty)
    await nettop.set(received: 1_800)
    await apps.sample()
    #expect(apps.pendingUsage.isEmpty)
    await nettop.set(received: 1_900)
    await apps.sample()
    #expect(apps.pendingUsage.map(\.bytes.received) == [100])
  }

  @Test("clear history drops a per-app sample that was in flight")
  func clearDropsInFlightAppSample() async throws {
    let fixture = try Fixture()
    let nettop = NettopStub()
    let apps = AppTrafficMonitor(snapshot: { await nettop.snapshot() })
    let monitor = fixture.makeMonitor(apps: apps)
    monitor.tick()
    await nettop.set(received: 1_000)
    await apps.sample()

    await nettop.holdNext()
    let inFlight = Task { await apps.sample() }
    await nettop.waitUntilHeld()
    try monitor.clearHistory()
    await nettop.finish(received: 1_500)
    await inFlight.value
    #expect(apps.pendingUsage.isEmpty)
    #expect(apps.pendingRecords.isEmpty)

    // Routine saves still only empty the buffer: socket accounting carries on.
    await nettop.set(received: 1_500)
    await apps.sample()
    await nettop.set(received: 1_600)
    await apps.sample()
    monitor.flush()
    #expect(apps.pendingUsage.isEmpty)
    await nettop.set(received: 1_650)
    await apps.sample()
    #expect(apps.pendingUsage.map(\.bytes.received) == [50])
  }

  @Test("legacy UserDefaults recovery is not imported into a new database")
  func freshDatabase() throws {
    let fixture = try Fixture()
    fixture.state.counters = ByteCounters(received: 9_000_000, sent: 2_000_000)
    fixture.monitor.tick()
    fixture.monitor.flush()
    #expect(try fixture.monitor.store?.total(since: nil) == .zero)
    #expect(try fixture.monitor.store?.checkpoint()?.counters == fixture.state.counters)
  }

  @Test("a temporarily unavailable boot time retains pending bytes until an atomic retry")
  func unavailableBootTimeOnSave() throws {
    let fixture = try Fixture()
    fixture.monitor.tick()
    fixture.monitor.flush()
    fixture.advance(received: 50)
    fixture.monitor.tick()
    let bootTime = fixture.state.bootTime
    fixture.state.bootTime = nil
    fixture.monitor.flush()
    #expect(fixture.monitor.storeError != nil)
    #expect(totalUsage(fixture.monitor.pendingRecords).received == 50)
    #expect(try fixture.monitor.store?.checkpoint()?.counters.received == 100)
    fixture.state.bootTime = bootTime
    fixture.monitor.flush()
    #expect(fixture.monitor.storeError == nil)
    #expect(try fixture.monitor.store?.total(since: nil).received == 50)
  }

  @Test("restart recovery waits for boot time without clearing its error or counting bytes twice")
  func unavailableBootTimeOnRestart() throws {
    let fixture = try Fixture()
    fixture.monitor.tick()
    fixture.monitor.flush()
    fixture.advance(received: 50)
    let bootTime = fixture.state.bootTime
    fixture.state.bootTime = nil
    let restarted = fixture.makeMonitor()
    restarted.tick()
    restarted.flush()
    #expect(restarted.storeError != nil)
    #expect(restarted.pendingRecords.isEmpty)
    fixture.state.bootTime = bootTime
    restarted.tick()
    #expect(totalUsage(restarted.pendingRecords).received == 50)
    #expect(restarted.pendingRecords.first?.isUnattributed == true)
    restarted.flush()
    restarted.tick()
    #expect(restarted.pendingRecords.isEmpty)
    #expect(try restarted.store?.total(since: nil).received == 50)
  }

  @Test("an invalid checkpoint starts a fresh boundary while retaining saved history")
  func corruptCheckpoint() throws {
    let fixture = try Fixture()
    fixture.monitor.tick()
    fixture.advance(received: 50)
    fixture.monitor.tick()
    fixture.monitor.flush()
    try fixture.sql("UPDATE counter_checkpoint SET payload = 'invalid JSON' WHERE id = 1")
    fixture.advance(received: 20)
    let restarted = fixture.makeMonitor()
    restarted.tick()
    #expect(restarted.pendingRecords.isEmpty)
    fixture.advance(received: 10)
    restarted.tick()
    restarted.flush()
    #expect(try restarted.store?.total(since: nil).received == 60)
    #expect(try restarted.store?.checkpoint()?.counters.received == 180)
  }

  @Test("traffic recovered after a long sleep gap does not inflate current speed or today's peak")
  func wakeRate() throws {
    let fixture = try Fixture()
    fixture.monitor.tick()
    fixture.advance(received: 50)
    fixture.monitor.tick()
    #expect(fixture.monitor.download == 50)
    fixture.state.uptime += 900
    fixture.state.counters = fixture.state.counters! + ByteCounters(received: 30, sent: 0)
    fixture.monitor.tick()
    #expect(fixture.monitor.download == 0)
    #expect(fixture.monitor.peakDownloadToday == 50)
    #expect(try fixture.monitor.store?.total(since: nil).received == 80)
  }

  @Test("per-app save failures do not hide successfully committed network history")
  func appWriteFailure() async throws {
    let fixture = try Fixture()
    let nettop = NettopStub()
    let apps = AppTrafficMonitor(snapshot: { await nettop.snapshot() })
    let monitor = fixture.makeMonitor(apps: apps, saveAppUsage: { _, _ in
      throw UsageStoreError.sqlite("test app failure")
    })
    monitor.tick()
    await nettop.set(received: 1_000)
    await apps.sample()
    fixture.advance(received: 50)
    monitor.tick()
    await nettop.set(received: 1_040)
    await apps.sample()
    let revision = monitor.historyRevision
    monitor.flush()
    #expect(monitor.storeError?.contains("app history") == true)
    #expect(monitor.historyRevision > revision)
    #expect(monitor.pendingRecords.isEmpty)
    #expect(totalUsage(monitor.committedRecords).received == 50)
    #expect(try monitor.store?.total(since: nil).received == 50)

    // The app's bytes are kept for a retry and are part of the saved Wi-Fi total: the Apps list
    // must not show them under Other as well.
    #expect(apps.pendingUsage.map(\.bytes.received) == [40])
    let model = AppUsageModel()
    await model.load(.day, from: monitor.store, now: fixture.state.origin.addingTimeInterval(fixture.state.uptime))
    let list = model.list(pendingApps: apps.pendingUsage, pendingWifi: totalUsage(monitor.pendingRecords))
    #expect(list.map(\.name) == ["curl", AppUsage.otherName])
    #expect(list.map(\.bytes.received) == [40, 10])
  }

  @MainActor
  private final class State {
    var counters: ByteCounters? = ByteCounters(received: 100, sent: 10)
    var uptime: TimeInterval = 0
    var bootTime: Date? = Date(timeIntervalSince1970: 1_799_000_000)
    let origin = Date(timeIntervalSince1970: 1_800_000_000)
    var snapshot = WiFiInfo.Snapshot(interfaceName: "en0", ssid: "Home", status: .connected,
                                    locationAuthorization: .authorizedAlways, locationServicesEnabled: true)
  }

  @MainActor
  private final class Fixture {
    let state = State()
    let url: URL
    lazy var monitor = makeMonitor()

    init() throws {
      url = FileManager.default.temporaryDirectory.appending(path: "wifi-monitor-\(UUID().uuidString)/usage.sqlite")
    }

    func makeMonitor(
      apps: AppTrafficMonitor = AppTrafficMonitor(),
      saveAppUsage: @escaping (UsageStore, [AppUsageRecord]) throws -> Void = { try $0.addAppUsage($1) }
    ) -> TrafficMonitor {
      let state = state
      let wifi = WiFiInfo(snapshotReader: { state.snapshot }, monitorsEvents: false)
      return TrafficMonitor(wifi: wifi, storeURL: url, apps: apps, readCounters: { _ in state.counters },
                            readBootTime: { state.bootTime },
                            dateNow: { state.origin.addingTimeInterval(state.uptime) }, uptimeNow: { state.uptime },
                            saveAppUsage: saveAppUsage)
    }

    func advance(received: UInt64, sent: UInt64 = 0) {
      state.uptime += 1
      state.counters = (state.counters ?? .zero) + ByteCounters(received: received, sent: sent)
    }

    func sql(_ query: String) throws {
      var db: OpaquePointer?
      #expect(sqlite3_open(url.path, &db) == SQLITE_OK)
      defer { sqlite3_close(db) }
      let result = sqlite3_exec(db, query, nil, nil, nil)
      if result != SQLITE_OK {
        throw UsageStoreError.sqlite(db.map { String(cString: sqlite3_errmsg($0)) } ?? "no database")
      }
    }
  }
}
