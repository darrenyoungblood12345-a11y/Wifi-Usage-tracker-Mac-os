import AppKit
import Observation
import WiFiTrackerCore

struct RateSample: Identifiable, Equatable, Sendable {
  let date: Date
  let download: Double
  let upload: Double
  var id: Date { date }
}

/// Samples every second; publishes buffered history immediately and commits it once a minute.
@MainActor
@Observable
final class TrafficMonitor {
  static let liveWindow: TimeInterval = 15 * 60
  private static let clockOrigin = ContinuousClock.now

  static func monotonicTime() -> TimeInterval {
    (ContinuousClock.now - clockOrigin) / .seconds(1)
  }

  private(set) var download: Double = 0
  private(set) var upload: Double = 0
  private(set) var samples: [RateSample] = []
  private(set) var totals = PeriodTotals.zero
  private(set) var peakDownloadToday: Double = 0
  private(set) var peakUploadToday: Double = 0
  private(set) var historyRevision = 0
  private(set) var historyEpoch = 0
  private(set) var storeError: String?
  private(set) var pendingRecords: [UsageRecord] = []
  /// Successful session commits, grouped by local hour to bridge background history reads.
  private(set) var committedRecords: [UsageRecord] = []

  let wifi: WiFiInfo
  let storeURL: URL
  let store: UsageStore?
  let apps = AppTrafficMonitor()

  @ObservationIgnored private var accounting = NetworkAccounting()
  @ObservationIgnored private var didRecoverCheckpoint = false
  @ObservationIgnored private var pending: [PendingKey: ByteCounters] = [:]
  @ObservationIgnored private var committed: [PendingKey: ByteCounters] = [:]
  @ObservationIgnored private var lastFlush: TimeInterval
  @ObservationIgnored private var day: Date
  @ObservationIgnored private var loop: Task<Void, Never>?
  @ObservationIgnored private var observers: [any NSObjectProtocol] = []
  @ObservationIgnored private var workspaceObservers: [any NSObjectProtocol] = []
  @ObservationIgnored private let readCounters: (String) -> ByteCounters?
  @ObservationIgnored private let readBootTime: () -> Date?
  @ObservationIgnored private let dateNow: () -> Date
  @ObservationIgnored private let uptimeNow: () -> TimeInterval
  @ObservationIgnored private let saveAppUsage: (UsageStore, [AppUsageRecord]) throws -> Void

  private struct PendingKey: Hashable {
    let bucket: Date
    let network: NetworkIdentity
  }

  init(
    wifi: WiFiInfo = WiFiInfo(),
    storeURL: URL = UsageStore.defaultURL,
    readCounters: @escaping (String) -> ByteCounters? = { InterfaceCounters.read(interface: $0) },
    readBootTime: @escaping () -> Date? = { SystemBoot.time() },
    dateNow: @escaping () -> Date = { .now },
    uptimeNow: @escaping () -> TimeInterval = { TrafficMonitor.monotonicTime() },
    saveAppUsage: @escaping (UsageStore, [AppUsageRecord]) throws -> Void = { try $0.addAppUsage($1) }
  ) {
    self.wifi = wifi
    self.storeURL = storeURL
    self.readCounters = readCounters
    self.readBootTime = readBootTime
    self.dateNow = dateNow
    self.uptimeNow = uptimeNow
    self.saveAppUsage = saveAppUsage
    lastFlush = uptimeNow()
    day = Calendar.current.startOfDay(for: dateNow())
    do {
      store = try UsageStore(url: storeURL)
    } catch {
      store = nil
      storeError = String(describing: error)
    }
  }

  func start(tracksApps: Bool = true) {
    guard loop == nil else { return }
    do {
      try store?.compact(olderThan: dateNow().addingTimeInterval(-30 * 86_400))
      try refreshTotals()
    } catch {
      storeError = String(describing: error)
    }
    tick()
    // Establish a database-owned baseline before any later recovery; legacy UserDefaults
    // checkpoints may be one sample behind and cannot safely be imported.
    flush()
    if tracksApps { apps.start() }
    observeLifecycle()
    loop = Task { [weak self] in
      while !Task.isCancelled {
        self?.tick()
        try? await Task.sleep(for: .seconds(1))
      }
    }
  }

  func stop() {
    loop?.cancel()
    loop = nil
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    observers = []
    workspaceObservers = []
    flush()
  }

  func refreshForPresentation() {
    tick()
    historyRevision += 1
    NetworkDiagnostics.write("presentation-refresh", fields: ["revision": String(historyRevision)])
  }

  func flush() {
    lastFlush = uptimeNow()
    guard let store else { return }
    guard didRecoverCheckpoint else { return }
    guard let bootTime = readBootTime() else {
      storeError = "Couldn’t read the system boot time. Usage is buffered until its checkpoint can be saved safely."
      return
    }
    let records = pendingRecords
    let checkpoint = accounting.checkpoint(bootTime: bootTime)
    do {
      try store.add(records, checkpoint: checkpoint)
    } catch {
      storeError = "Couldn’t save Wi-Fi history: \(error)"
      NetworkDiagnostics.write("flush-error")
      return
    }

    records.forEach { record in
      let hour = Calendar.current.dateInterval(of: .hour, for: record.bucket)?.start ?? record.bucket
      committed[PendingKey(bucket: hour, network: record.identity), default: .zero] += record.bytes
    }
    committedRecords = self.records(from: committed)
    pending = [:]
    pendingRecords = []
    historyRevision += 1
    NetworkDiagnostics.write("flush", fields: [
      "revision": String(historyRevision),
      "download": String(totalUsage(records).received),
      "upload": String(totalUsage(records).sent),
      "checkpointDownload": String(checkpoint?.counters.received ?? 0),
      "checkpointUpload": String(checkpoint?.counters.sent ?? 0),
    ])

    var errors: [String] = []
    do {
      try refreshTotals()
    } catch {
      errors.append("Couldn’t read usage totals: \(error)")
    }
    do {
      try saveAppUsage(store, apps.pendingRecords)
      apps.clearPending()
    } catch {
      errors.append("Couldn’t save app history: \(error)")
    }
    storeError = errors.isEmpty ? nil : errors.joined(separator: "\n")
  }

  func clearHistory() throws {
    // Take a fresh boundary so the next launch cannot recover bytes the user just cleared.
    wifi.refresh()
    var baseline = NetworkAccounting()
    if let sample = currentSample(date: dateNow(), uptime: uptimeNow()) {
      _ = baseline.update(sample)
    }
    let checkpoint = readBootTime().flatMap { baseline.checkpoint(bootTime: $0) }
    guard let store else { throw UsageStoreError.sqlite(storeError ?? "History storage is unavailable") }
    try store.deleteAll(checkpoint: checkpoint)
    accounting = baseline
    didRecoverCheckpoint = true
    pending = [:]
    pendingRecords = []
    committed = [:]
    committedRecords = []
    apps.clearPending()
    totals = .zero
    historyEpoch += 1
    historyRevision += 1
  }

  func exportCSV() throws -> String {
    flush()
    if let storeError { throw UsageStoreError.sqlite(storeError) }
    return try store?.exportCSV() ?? ""
  }

  // Internal for deterministic integration tests with injected clock/counter readers.
  func tick() {
    let date = dateNow()
    let uptime = uptimeNow()
    defer {
      // Persist buffered traffic even if this counter reading is unavailable.
      if uptime - lastFlush >= 60 { flush() }
    }
    wifi.refresh()
    rollOverDayIfNeeded(date)
    var fields = wifi.diagnosticFields
    guard let sample = currentSample(date: date, uptime: uptime) else {
      accounting.invalidateContinuity()
      record(RateSample(date: date, download: 0, upload: 0))
      fields["counterAvailable"] = "false"
      NetworkDiagnostics.write("sample", fields: fields)
      return
    }
    fields["counterAvailable"] = "true"
    fields["received"] = String(sample.counters.received)
    fields["sent"] = String(sample.counters.sent)
    NetworkDiagnostics.write("sample", fields: fields)

    let delta: NetworkDelta?
    if !didRecoverCheckpoint {
      do {
        let checkpoint = try store?.checkpoint()
        if let checkpoint {
          guard let bootTime = readBootTime() else {
            storeError = "Couldn’t read the system boot time to recover saved usage."
            return
          }
          delta = accounting.restore(checkpoint, bootTime: bootTime, sample: sample)
        } else {
          delta = accounting.update(sample)
        }
        didRecoverCheckpoint = true
      } catch is DecodingError {
        // An unreadable checkpoint cannot identify missed bytes. Start from the current
        // boundary, keeping stored history intact and replacing the checkpoint on save.
        delta = accounting.update(sample)
        didRecoverCheckpoint = true
        NetworkDiagnostics.write("checkpoint-invalid")
      } catch {
        storeError = "Couldn’t read the Wi-Fi checkpoint: \(error)"
        return
      }
      // Recovered bytes have no trustworthy live speed or network identity.
      record(RateSample(date: date, download: 0, upload: 0))
    } else {
      delta = accounting.update(sample)
      record(RateSample(
        date: date,
        download: delta.map { $0.isLive && $0.elapsed > 0 ? Double($0.bytes.received) / $0.elapsed : 0 } ?? 0,
        upload: delta.map { $0.isLive && $0.elapsed > 0 ? Double($0.bytes.sent) / $0.elapsed : 0 } ?? 0
      ))
    }
    if let delta, delta.bytes.total > 0 {
      add(delta.bytes, at: date, network: delta.network)
    }
  }

  private func currentSample(date: Date, uptime: TimeInterval) -> NetworkSample? {
    guard let interface = wifi.interfaceName, let counters = readCounters(interface) else { return nil }
    return NetworkSample(date: date, uptime: uptime, interface: interface, counters: counters,
                         network: wifi.networkIdentity, continuity: wifi.connectionRevision)
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

  private func add(_ bytes: ByteCounters, at date: Date, network: NetworkIdentity) {
    pending[PendingKey(bucket: minuteBucket(for: date), network: network), default: .zero] += bytes
    pendingRecords = records(from: pending)
    totals = totals + bytes
  }

  private func records(from values: [PendingKey: ByteCounters]) -> [UsageRecord] {
    values.map {
      UsageRecord(bucket: $0.key.bucket, network: $0.key.network.storageName,
                  bytes: $0.value, isUnattributed: $0.key.network.isUnattributed)
    }
  }

  private func rollOverDayIfNeeded(_ now: Date) {
    let today = Calendar.current.startOfDay(for: now)
    guard today != day else { return }
    day = today
    peakDownloadToday = 0
    peakUploadToday = 0
    flush()
  }

  private func refreshTotals() throws {
    guard let store else { return }
    totals = try store.periodTotals(now: dateNow())
  }

  private func observeLifecycle() {
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.tick()
        self?.flush()
      }
    })
    observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated { self?.refreshForPresentation() }
    })
    let workspace = NSWorkspace.shared.notificationCenter
    workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.tick()
        self?.flush()
        self?.accounting.invalidateContinuity()
        NetworkDiagnostics.write("sleep")
      }
    })
    workspaceObservers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.accounting.invalidateContinuity()
        self?.refreshForPresentation()
        self?.flush()
        NetworkDiagnostics.write("wake")
      }
    })
  }
}
