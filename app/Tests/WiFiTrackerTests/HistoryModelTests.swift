import Foundation
import Testing
import WiFiTrackerCore
@testable import WiFiTracker

private actor HistoryReadGate {
  private var continuation: CheckedContinuation<[UsageRecord], any Error>?
  private var hasStarted = false
  private var startWaiters: [CheckedContinuation<Void, Never>] = []

  func read(_ interval: DateInterval) async throws -> [UsageRecord] {
    hasStarted = true
    startWaiters.forEach { $0.resume() }
    startWaiters = []
    return try await withCheckedThrowingContinuation { continuation = $0 }
  }

  func waitUntilStarted() async {
    guard !hasStarted else { return }
    await withCheckedContinuation { startWaiters.append($0) }
  }

  func finish(_ records: [UsageRecord]) {
    continuation?.resume(returning: records)
    continuation = nil
  }
}

private struct HistoryReadFailure: LocalizedError {
  var errorDescription: String? { "The history database is unavailable." }
}

@Suite("Live history presentation")
@MainActor
struct HistoryModelTests {
  let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
  }()

  var now: Date { date(8, 14, 37) }

  func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
  }

  func record(_ bytes: UInt64, network: String = "Home", bucket: Date? = nil, isUnattributed: Bool = false) -> UsageRecord {
    UsageRecord(bucket: bucket ?? date(8, 14), network: network, bytes: ByteCounters(received: bytes, sent: 0), isUnattributed: isUnattributed)
  }

  func update(_ model: HistoryModel, pending: [UsageRecord] = [], committed: [UsageRecord] = [], revision: Int = 0, epoch: Int = 0, now: Date? = nil) {
    model.updateLive(pending: pending, committed: committed, revision: revision, epoch: epoch, now: now ?? self.now, calendar: calendar)
  }

  @Test("shows buffered usage in network rows, totals and charts before the first disk read")
  func pendingBeforeLoad() {
    let model = HistoryModel()
    update(model, pending: [record(25, network: "Cafe", bucket: date(8, 14, 37))])

    #expect(model.total.received == 25)
    #expect(model.networks == [NetworkUsage(network: "Cafe", bytes: ByteCounters(received: 25, sent: 0))])
    #expect(model.points.last?.bytes.received == 25)
    #expect(model.points.count == 24)
  }

  @Test("keeps bytes visible through a flush and counts them once after the disk read")
  func flushBridge() async {
    let model = HistoryModel()
    let saved = record(100, bucket: date(8, 13, 10))
    update(model, pending: [record(25)])
    await model.load(records: { _ in [saved] })
    #expect(model.total.received == 125)

    update(model, committed: [record(25)], revision: 1)
    #expect(model.total.received == 125)

    let gate = HistoryReadGate()
    let load = Task { await model.load(records: { try await gate.read($0) }) }
    await gate.waitUntilStarted()
    update(model, pending: [record(7)], committed: [record(25)], revision: 1)
    #expect(model.total.received == 132)
    await gate.finish([saved, record(25, bucket: date(8, 14, 36))])
    await load.value

    #expect(model.total.received == 132)
    #expect(model.networks.first?.bytes.received == 132)
    #expect(model.points.reduce(UInt64(0)) { $0 + $1.bytes.received } == 132)
  }

  @Test("loads real SQLite history off the main actor and overlays buffered traffic once")
  func sqliteHistory() async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: "WiFiTracker-history-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = try UsageStore(url: directory.appending(path: "usage.sqlite"))
    try store.add([record(100, bucket: date(8, 13, 10)), record(20, network: "Cafe", bucket: date(8, 14, 30))])

    let model = HistoryModel()
    update(model, pending: [record(5, network: "Cafe")], committed: [record(20, network: "Cafe")], revision: 1)
    await model.load(from: store, isCurrent: { true })

    #expect(model.total.received == 125)
    #expect(model.networks.first?.bytes.received == 100)
    #expect(model.networks.last?.bytes.received == 25)
    #expect(model.points.last?.bytes.received == 25)
  }

  @Test("retains multiple coalesced commits and rejects a read that spans another flush")
  func multipleCommitsDuringRead() async {
    let model = HistoryModel()
    let saved = record(100, bucket: date(8, 13))
    update(model)
    await model.load(records: { _ in [saved] })
    update(model, pending: [record(25)])

    let gate = HistoryReadGate()
    let staleLoad = Task { await model.load(records: { try await gate.read($0) }) }
    await gate.waitUntilStarted()
    update(model, committed: [record(60)], revision: 2)
    #expect(model.total.received == 160)
    await gate.finish([saved, record(25)])
    await staleLoad.value
    #expect(model.total.received == 160)

    let latest = record(60)
    await model.load(records: { _ in [saved, latest] })
    #expect(model.total.received == 160)
  }

  @Test("an older request for the same range cannot replace a newer saved snapshot")
  func outOfOrderReads() async {
    let model = HistoryModel()
    update(model)
    let gate = HistoryReadGate()
    let oldLoad = Task { await model.load(records: { try await gate.read($0) }) }
    await gate.waitUntilStarted()
    let fresh = record(200)
    await model.load(records: { _ in [fresh] })
    await gate.finish([record(50)])
    await oldLoad.value

    #expect(model.total.received == 200)
  }

  @Test("cancelled reads cannot erase the saved snapshot")
  func cancelledRead() async {
    let model = HistoryModel()
    update(model)
    let saved = record(100)
    await model.load(records: { _ in [saved] })
    let gate = HistoryReadGate()
    let cancelledLoad = Task { await model.load(records: { try await gate.read($0) }) }
    await gate.waitUntilStarted()
    cancelledLoad.cancel()
    await gate.finish([])
    await cancelledLoad.value

    #expect(model.total.received == 100)
    #expect(model.loadError == nil)
  }

  @Test("changing the selected range rejects an old read and uses the correct interval")
  func rangeChange() async {
    let model = HistoryModel()
    update(model)
    let gate = HistoryReadGate()
    let dayLoad = Task { await model.load(records: { try await gate.read($0) }) }
    await gate.waitUntilStarted()
    model.range = .week
    update(model, pending: [record(25, network: "Cafe")])
    let weekSaved = record(100, bucket: date(3, 10))
    await model.load(records: { _ in [weekSaved] })
    await gate.finish([record(999)])
    await dayLoad.value

    #expect(model.total.received == 125)
    #expect(model.points.count == 7)
    #expect(model.interval == HistoryRange.week.interval(now: now, calendar: calendar))
  }

  @Test("read failures preserve the last good snapshot and continue showing live traffic")
  func readFailure() async {
    let model = HistoryModel()
    update(model)
    let saved = record(100)
    await model.load(records: { _ in [saved] })
    update(model, pending: [record(25, network: "Cafe")])
    await model.load(records: { _ in throw HistoryReadFailure() })

    #expect(model.total.received == 125)
    #expect(model.loadError?.contains("database is unavailable") == true)
    update(model, pending: [record(35, network: "Cafe")])
    #expect(model.total.received == 135)
    await model.load(records: { _ in [saved] })
    #expect(model.total.received == 135)
    #expect(model.loadError == nil)
  }

  @Test("history clearing removes cached and bridged bytes and rejects the old read")
  func clearHistory() async {
    let model = HistoryModel()
    update(model, committed: [record(25)], revision: 1)
    let saved = record(125)
    await model.load(records: { _ in [saved] })
    let gate = HistoryReadGate()
    let oldLoad = Task { await model.load(records: { try await gate.read($0) }) }
    await gate.waitUntilStarted()
    update(model, epoch: 1)
    #expect(model.total == .zero)
    #expect(model.networks.isEmpty)
    await gate.finish([saved])
    await oldLoad.value
    #expect(model.total == .zero)

    update(model, pending: [record(7)], epoch: 1)
    #expect(model.total.received == 7)
  }

  @Test("filters pending and committed bytes to a half-open selected interval")
  func intervalBoundaries() async {
    let model = HistoryModel()
    let interval = HistoryRange.day.interval(now: now, calendar: calendar)
    let before = record(1_000, bucket: interval.start.addingTimeInterval(-60))
    let start = record(25, bucket: interval.start)
    let end = record(2_000, bucket: interval.end)
    update(model, pending: [before, start, end], committed: [before, record(10), end])
    #expect(model.total.received == 35)

    update(model, pending: [record(5, bucket: date(8, 15))], committed: [record(10)], now: date(8, 15, 1))
    #expect(model.total.received == 15)
    #expect(model.points.last?.bytes.received == 5)
  }

  @Test("keeps unattributed bytes separate from legacy labels and named networks")
  func attributionIdentity() async {
    let model = HistoryModel()
    let legacy = record(100, network: "Wi-Fi")
    let unknown = record(20, network: "Wi-Fi", isUnattributed: true)
    update(model, pending: [unknown, record(30, network: "Cafe")])
    await model.load(records: { _ in [legacy] })

    #expect(model.total.received == 150)
    #expect(model.networks.count == 3)
    #expect(model.networks.first?.displayName == "Wi-Fi")
    #expect(model.networks.filter(\.isUnattributed).first?.bytes.received == 20)
    update(model, pending: [record(5, network: "Cafe")], committed: [unknown, record(30, network: "Cafe")], revision: 1)
    #expect(model.total.received == 155)
    #expect(model.networks.filter(\.isUnattributed).first?.bytes.received == 20)
  }

  @Test("checks the monitor revision even before its live update callback is delivered")
  func revisionGuardBeforeCallback() async {
    let model = HistoryModel()
    update(model, pending: [record(25)])
    let gate = HistoryReadGate()
    var revisionIsCurrent = true
    let load = Task {
      await model.load(records: { try await gate.read($0) }, isCurrent: { revisionIsCurrent })
    }
    await gate.waitUntilStarted()
    revisionIsCurrent = false
    await gate.finish([record(25)])
    await load.value

    #expect(model.total.received == 25)
  }
}
