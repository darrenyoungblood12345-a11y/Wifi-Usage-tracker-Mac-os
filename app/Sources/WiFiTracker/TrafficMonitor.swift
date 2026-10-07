import AppKit
import Observation
import WiFiTrackerCore

struct RateSample: Identifiable, Equatable, Sendable {
  let date: Date
  /// Bytes per second.
  let download: Double
  let upload: Double
  var id: Date { date }
}

/// Samples the Wi-Fi interface's byte counters every second, publishes live speeds,
/// and records usage per minute and network.
@MainActor
@Observable
final class TrafficMonitor {
  static let liveWindow: TimeInterval = 15 * 60

  private(set) var download: Double = 0
  private(set) var upload: Double = 0
  private(set) var samples: [RateSample] = []
  private(set) var totals = PeriodTotals.zero
  private(set) var peakDownloadToday: Double = 0
  private(set) var peakUploadToday: Double = 0
  /// Bumped whenever stored history changes, so history views know to reload.
  private(set) var historyRevision = 0
  private(set) var storeError: String?

  let wifi: WiFiInfo
  let store: UsageStore?

  @ObservationIgnored private var previous: ByteCounters?
  @ObservationIgnored private var previousInterface: String?
  @ObservationIgnored private var previousInstant: ContinuousClock.Instant?
  @ObservationIgnored private var pending: [PendingKey: ByteCounters] = [:]
  @ObservationIgnored private var lastFlush = ContinuousClock.now
  @ObservationIgnored private var day = Calendar.current.startOfDay(for: .now)
  @ObservationIgnored private var loop: Task<Void, Never>?
  @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

  private struct PendingKey: Hashable {
    let minute: Date
    let network: String
  }

  /// The checkpoint belongs to the database it was flushed to, so a dev database never steals real catch-up bytes.
  @ObservationIgnored private let checkpointKey: String

  init(wifi: WiFiInfo = WiFiInfo(), storeURL: URL = UsageStore.defaultURL) {
    self.wifi = wifi
    checkpointKey = storeURL == UsageStore.defaultURL ? "counterCheckpoint" : "counterCheckpoint:\(storeURL.path)"
    do {
      store = try UsageStore(url: storeURL)
    } catch {
      store = nil
      storeError = String(describing: error)
    }
  }

  func start() {
    guard loop == nil else { return }
    try? store?.compact(olderThan: .now.addingTimeInterval(-30 * 86_400))
    refreshTotals()
    catchUpSinceLastRun()

    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification, object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.flush() }
    }
    loop = Task { [weak self] in
      while !Task.isCancelled {
        self?.tick()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  /// Writes buffered usage to disk and refreshes the period totals from the store.
  func flush() {
    lastFlush = .now
    guard let store else { return }
    let records = pending.map { UsageRecord(bucket: $0.key.minute, network: $0.key.network, bytes: $0.value) }
    do {
      try store.add(records)
      pending = [:]
      saveCheckpoint()
      totals = try store.periodTotals()
      historyRevision += 1
      storeError = nil
    } catch {
      storeError = String(describing: error)
    }
  }

  func clearHistory() throws {
    try store?.deleteAll()
    pending = [:]
    totals = .zero
    historyRevision += 1
  }

  func exportCSV() throws -> String {
    flush()
    return try store?.exportCSV() ?? ""
  }

  // MARK: Sampling

  private func tick() {
    let now = Date.now
    let instant = ContinuousClock.now
    wifi.refreshIfStale()
    rollOverDayIfNeeded(now)

    let interface = wifi.interfaceName
    guard let current = InterfaceCounters.read(interface: interface) else {
      record(RateSample(date: now, download: 0, upload: 0))
      return
    }
    defer {
      self.previous = current
      self.previousInterface = interface
      self.previousInstant = instant
    }
    guard let previous, let previousInstant, previousInterface == interface else { return }

    let delta = current.delta(since: previous)
    let elapsed = (instant - previousInstant) / .seconds(1)
    guard elapsed > 0 else { return }

    record(RateSample(date: now, download: Double(delta.received) / elapsed, upload: Double(delta.sent) / elapsed))
    if delta.total > 0 {
      add(delta, at: now, network: wifi.networkName)
    }
    if instant - lastFlush >= .seconds(60) {
      flush()
    }
  }

  private func record(_ sample: RateSample) {
    download = sample.download
    upload = sample.upload
    peakDownloadToday = max(peakDownloadToday, sample.download)
    peakUploadToday = max(peakUploadToday, sample.upload)

    let cutoff = sample.date.addingTimeInterval(-Self.liveWindow)
    let stale = samples.prefix { $0.date < cutoff }.count
    samples.removeFirst(stale)
    samples.append(sample)
  }

  private func add(_ bytes: ByteCounters, at date: Date, network: String) {
    let key = PendingKey(minute: minuteBucket(for: date), network: network)
    pending[key] = (pending[key] ?? .zero) + bytes
    totals = totals + bytes
  }

  private func rollOverDayIfNeeded(_ now: Date) {
    let today = Calendar.current.startOfDay(for: now)
    guard today != day else { return }
    day = today
    peakDownloadToday = 0
    peakUploadToday = 0
    flush()
  }

  private func refreshTotals() {
    guard let store else { return }
    totals = (try? store.periodTotals()) ?? .zero
  }

  // MARK: Catching up on time the app wasn't running

  /// The last counter reading that has been written to disk. Kernel counters keep running while
  /// the app is closed, so on the next launch in the same boot session the difference is real usage.
  private struct Checkpoint: Codable {
    let bootTime: Date
    let interface: String
    let network: String
    let received: UInt64
    let sent: UInt64
  }

  private func saveCheckpoint() {
    guard let previous, let previousInterface, let bootTime = SystemBoot.time() else { return }
    let checkpoint = Checkpoint(
      bootTime: bootTime,
      interface: previousInterface,
      network: wifi.networkName,
      received: previous.received,
      sent: previous.sent
    )
    UserDefaults.standard.set(try? JSONEncoder().encode(checkpoint), forKey: checkpointKey)
  }

  private func catchUpSinceLastRun() {
    guard let data = UserDefaults.standard.data(forKey: checkpointKey),
          let checkpoint = try? JSONDecoder().decode(Checkpoint.self, from: data),
          let bootTime = SystemBoot.time(),
          abs(bootTime.timeIntervalSince(checkpoint.bootTime)) < 5,
          let current = InterfaceCounters.read(interface: checkpoint.interface)
    else { return }

    let missed = current.delta(since: ByteCounters(received: checkpoint.received, sent: checkpoint.sent))
    previous = current
    previousInterface = checkpoint.interface
    previousInstant = .now
    guard missed.total > 0 else { return }
    add(missed, at: .now, network: checkpoint.network)
    flush()
  }
}
