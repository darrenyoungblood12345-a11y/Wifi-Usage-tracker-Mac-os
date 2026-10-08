import Darwin
import Foundation
import Observation
import WiFiTrackerCore

/// Live speed of one app, in bytes per second.
struct AppRate: Equatable, Sendable {
  let download: Double
  let upload: Double
}

/// Samples Wi-Fi traffic per app every couple of seconds for live speeds, and buffers it per hour
/// until `TrafficMonitor` flushes it to the store.
@MainActor
@Observable
final class AppTrafficMonitor {
  static let interval: Duration = .seconds(2)

  /// Speed per app id over the latest sample. Apps that moved nothing are left out.
  private(set) var rates: [String: AppRate] = [:]
  /// Why per-app sampling isn't working, if it isn't.
  private(set) var unavailableReason: String?
  /// Usage per app that hasn't been written to the store yet.
  private(set) var pendingUsage: [AppUsage] = []

  @ObservationIgnored private var pending: [PendingKey: ByteCounters] = [:]
  @ObservationIgnored private var names: [String: String] = [:]
  @ObservationIgnored private let sampler = AppTrafficSampler()
  @ObservationIgnored private var loop: Task<Void, Never>?

  private struct PendingKey: Hashable {
    let hour: Date
    let app: String
  }

  func start() {
    guard loop == nil else { return }
    loop = Task { [weak self] in
      while !Task.isCancelled {
        await self?.sample()
        try? await Task.sleep(for: Self.interval)
      }
    }
  }

  var pendingRecords: [AppUsageRecord] {
    pending.map { AppUsageRecord(bucket: $0.key.hour, app: $0.key.app, name: names[$0.key.app] ?? $0.key.app, bytes: $0.value) }
  }

  /// Call once `pendingRecords` are safely stored.
  func clearPending() {
    pending = [:]
    names = [:]
    pendingUsage = []
  }

  private func sample() async {
    do {
      let sample = try await sampler.sample()
      unavailableReason = nil
      record(sample)
    } catch {
      unavailableReason = "Per-app usage isn’t available: \(error.localizedDescription)"
      rates = [:]
    }
  }

  private func record(_ sample: AppTrafficSample) {
    rates = sample.elapsed > 0
      ? Dictionary(uniqueKeysWithValues: sample.apps.map { app in
        (app.id, AppRate(download: Double(app.bytes.received) / sample.elapsed, upload: Double(app.bytes.sent) / sample.elapsed))
      })
      : [:]
    guard !sample.apps.isEmpty else { return }

    let hour = hourBucket(for: .now)
    sample.apps.forEach { app in
      pending[PendingKey(hour: hour, app: app.id), default: .zero] += app.bytes
      names[app.id] = app.name
    }
    pendingUsage = pending
      .reduce(into: [String: ByteCounters]()) { $0[$1.key.app, default: .zero] += $1.value }
      .map { AppUsage(id: $0.key, name: names[$0.key] ?? $0.key, bytes: $0.value) }
  }
}

/// Bytes per app since the previous sample, and the seconds that covers.
struct AppTrafficSample: Sendable {
  let apps: [AppUsage]
  let elapsed: Double
}

/// Takes `nettop` snapshots off the main thread and turns them into bytes per app.
actor AppTrafficSampler {
  private var tracker = SocketDeltaTracker()
  private var identities: [Int32: (process: String, identity: AppIdentity)] = [:]
  private var previousInstant: ContinuousClock.Instant?

  func sample() async throws -> AppTrafficSample {
    let output = try await Nettop.snapshot()
    let instant = ContinuousClock.now
    let elapsed = previousInstant.map { (instant - $0) / .seconds(1) } ?? 0
    previousInstant = instant

    let sockets = parseNettop(output)
    let traffic = tracker.update(sockets, at: .now)
    let live = Set(sockets.map(\.pid))
    identities = identities.filter { live.contains($0.key) }

    let apps = traffic.reduce(into: [String: AppUsage]()) { apps, process in
      let identity = identity(for: process)
      apps[identity.id, default: AppUsage(id: identity.id, name: identity.name, bytes: .zero)].bytes += process.bytes
    }
    return AppTrafficSample(apps: Array(apps.values), elapsed: elapsed)
  }

  /// Cached per pid, and looked up again if the pid now belongs to a different process.
  private func identity(for process: ProcessTraffic) -> AppIdentity {
    if let cached = identities[process.pid], cached.process == process.process { return cached.identity }
    let identity = AppIdentity.resolve(pid: process.pid, process: process.process)
    identities[process.pid] = (process.process, identity)
    return identity
  }
}

/// Which app a process's traffic is counted under.
struct AppIdentity: Equatable, Sendable {
  /// Bundle identifier for apps (or the bundle path if it has none), executable name otherwise.
  let id: String
  let name: String

  /// Helpers count as the app bundle they live in, and XPC services (like Safari's networking
  /// process) as the app that launched them. Anything else is named after its executable.
  static func resolve(pid: Int32, process: String) -> AppIdentity {
    guard let path = executablePath(of: pid) else { return AppIdentity(id: process, name: process) }
    if let bundle = outermostAppBundle(containing: path) {
      return app(at: bundle)
    }
    if isXPCService(path), let owner = responsiblePID(of: pid), owner != pid,
       let ownerPath = executablePath(of: owner), let bundle = outermostAppBundle(containing: ownerPath) {
      return app(at: bundle)
    }
    let name = URL(fileURLWithPath: path).lastPathComponent
    return AppIdentity(id: name, name: name)
  }

  private static func app(at bundlePath: String) -> AppIdentity {
    let info = NSDictionary(contentsOfFile: bundlePath + "/Contents/Info.plist")
    let displayName = FileManager.default.displayName(atPath: bundlePath)
    return AppIdentity(
      id: info?["CFBundleIdentifier"] as? String ?? bundlePath,
      name: displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
    )
  }

  private static func executablePath(of pid: Int32) -> String? {
    var buffer = [UInt8](repeating: 0, count: 4 * Int(MAXPATHLEN))
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
  }

  /// The process macOS holds responsible for `pid` (the app behind an XPC service), via libquarantine's
  /// `responsibility_get_pid_responsible_for_pid`, which is exported but not in the public headers.
  private static func responsiblePID(of pid: Int32) -> Int32? {
    guard let responsibleFor else { return nil }
    let owner = responsibleFor(pid)
    return owner > 0 ? owner : nil
  }

  private static let responsibleFor: (@convention(c) (Int32) -> Int32)? = {
    guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "responsibility_get_pid_responsible_for_pid") else { return nil }
    return unsafeBitCast(symbol, to: (@convention(c) (Int32) -> Int32).self)
  }()
}

/// Runs `/usr/bin/nettop` for one snapshot of Wi-Fi sockets.
///
/// A long-running `nettop` busy-polls at over 100% CPU, while one snapshot costs about 15 ms.
enum Nettop {
  static let url = URL(fileURLWithPath: "/usr/bin/nettop")
  static let arguments = ["-L", "1", "-n", "-x", "-J", "bytes_in,bytes_out", "-t", "wifi"]

  struct Failure: LocalizedError {
    let errorDescription: String?
  }

  /// Runs on a dispatch queue so the blocking read never ties up the main thread or Swift's worker pool.
  static func snapshot() async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .utility).async {
        continuation.resume(with: Result { try run() })
      }
    }
  }

  private static func run() throws -> String {
    let process = Process()
    process.executableURL = url
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()

    let watchdog = DispatchWorkItem { [process] in process.terminate() }
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: watchdog)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    watchdog.cancel()

    guard process.terminationStatus == 0 else {
      throw Failure(errorDescription: "nettop exited with status \(process.terminationStatus)")
    }
    return String(decoding: data, as: UTF8.self)
  }
}
