import Foundation

/// Separates unknown attribution from a real network with the same display name.
public enum NetworkIdentity: Hashable, Codable, Sendable {
  case named(String)
  case unattributed

  public var storageName: String {
    switch self {
    case .named(let name): name
    case .unattributed: ""
    }
  }

  public var displayName: String {
    switch self {
    case .named(let name): name
    case .unattributed: "Unattributed Wi-Fi"
    }
  }

  public var isUnattributed: Bool { self == .unattributed }
}

/// One successful counter read together with the connection identity observed with it.
public struct NetworkSample: Equatable, Sendable {
  public let date: Date
  public let uptime: TimeInterval
  public let interface: String
  public let counters: ByteCounters
  /// `nil` means disconnected or off; `.unattributed` means connected without a readable name.
  public let network: NetworkIdentity?
  /// Changes when connection events establish that equal names are not a continuous connection.
  public let continuity: Int

  public init(
    date: Date,
    uptime: TimeInterval,
    interface: String,
    counters: ByteCounters,
    network: NetworkIdentity?,
    continuity: Int = 0
  ) {
    self.date = date
    self.uptime = uptime
    self.interface = interface
    self.counters = counters
    self.network = network
    self.continuity = continuity
  }
}

/// The counter boundary committed atomically with usage, independent of network attribution.
public struct CounterCheckpoint: Equatable, Codable, Sendable {
  public let bootTime: Date
  public let interface: String
  public let counters: ByteCounters
  public let date: Date

  public init(bootTime: Date, interface: String, counters: ByteCounters, date: Date) {
    self.bootTime = bootTime
    self.interface = interface
    self.counters = counters
    self.date = date
  }
}

public struct NetworkDelta: Equatable, Sendable {
  public let bytes: ByteCounters
  public let network: NetworkIdentity
  public let elapsed: TimeInterval
  /// False when bytes span a recovery gap and cannot represent the current speed.
  public let isLive: Bool

  public init(bytes: ByteCounters, network: NetworkIdentity, elapsed: TimeInterval, isLive: Bool = true) {
    self.bytes = bytes
    self.network = network
    self.elapsed = elapsed
    self.isLive = isLive
  }
}

/// Counts comparable interface readings once, attributing only observed continuous intervals.
public struct NetworkAccounting: Sendable {
  private var previous: NetworkSample?
  private var continuityInvalidated = false
  private let maximumAttributionGap: TimeInterval

  public init(maximumAttributionGap: TimeInterval = 3) {
    self.maximumAttributionGap = maximumAttributionGap
  }

  /// Retains the last counters so traffic during a missed read or wake is preserved.
  public mutating func invalidateContinuity() {
    continuityInvalidated = true
  }

  public mutating func update(_ sample: NetworkSample) -> NetworkDelta? {
    // Do not let an out-of-order sample move the counter boundary back and recount bytes.
    if let previous, sample.uptime < previous.uptime {
      continuityInvalidated = true
      return nil
    }

    let previousSample = previous
    let wasInvalidated = continuityInvalidated
    previous = sample
    continuityInvalidated = false

    guard let previousSample, previousSample.interface == sample.interface else { return nil }

    let bytes = sample.counters.delta(since: previousSample.counters)
    guard bytes != .zero else { return nil }

    let elapsed = sample.uptime - previousSample.uptime
    // systemUptime can exclude sleep. Wall time also guards gaps when wake events are missed.
    let wallElapsed = sample.date.timeIntervalSince(previousSample.date)
    let countersReset = sample.counters.received < previousSample.counters.received
      || sample.counters.sent < previousSample.counters.sent
    let isLive = !wasInvalidated
      && !countersReset
      && elapsed > 0
      && elapsed <= maximumAttributionGap
      && wallElapsed > 0
      && wallElapsed <= maximumAttributionGap
    let canAttribute = isLive && sample.continuity == previousSample.continuity

    let network: NetworkIdentity
    if canAttribute,
      case .named(let name)? = sample.network,
      previousSample.network == sample.network
    {
      network = .named(name)
    } else {
      network = .unattributed
    }

    return NetworkDelta(bytes: bytes, network: network, elapsed: elapsed, isLive: isLive)
  }

  /// The unobserved interval while closed is always unattributed, even when endpoint names match.
  /// Every restore establishes the fresh reading as the next baseline, including a rejected checkpoint.
  public mutating func restore(
    _ checkpoint: CounterCheckpoint,
    bootTime: Date,
    sample: NetworkSample
  ) -> NetworkDelta? {
    previous = sample
    continuityInvalidated = false

    guard abs(checkpoint.bootTime.timeIntervalSince(bootTime)) <= 5,
      checkpoint.interface == sample.interface
    else { return nil }

    let bytes = sample.counters.delta(since: checkpoint.counters)
    guard bytes != .zero else { return nil }

    return NetworkDelta(
      bytes: bytes,
      network: .unattributed,
      elapsed: max(0, sample.date.timeIntervalSince(checkpoint.date)),
      isLive: false
    )
  }

  public func checkpoint(bootTime: Date) -> CounterCheckpoint? {
    guard let previous else { return nil }
    return CounterCheckpoint(
      bootTime: bootTime,
      interface: previous.interface,
      counters: previous.counters,
      date: previous.date
    )
  }
}
