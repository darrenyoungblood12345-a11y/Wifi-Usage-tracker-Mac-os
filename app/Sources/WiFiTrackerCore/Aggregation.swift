import Foundation

/// Bytes moved on one network during one time bucket (a minute, or an hour once compacted).
public struct UsageRecord: Equatable, Sendable {
  public var bucket: Date
  public var network: String
  public var bytes: ByteCounters

  public init(bucket: Date, network: String, bytes: ByteCounters) {
    self.bucket = bucket
    self.network = network
    self.bytes = bytes
  }
}

public enum Granularity: Sendable {
  case hour, day, month

  public var component: Calendar.Component {
    switch self {
    case .hour: .hour
    case .day: .day
    case .month: .month
    }
  }
}

/// Usage summed over one calendar bucket, ready to chart.
public struct UsagePoint: Equatable, Identifiable, Sendable {
  public var date: Date
  public var bytes: ByteCounters
  public var id: Date { date }

  public init(date: Date, bytes: ByteCounters) {
    self.date = date
    self.bytes = bytes
  }
}

public struct NetworkUsage: Equatable, Identifiable, Sendable {
  public var network: String
  public var bytes: ByteCounters
  public var id: String { network }

  public init(network: String, bytes: ByteCounters) {
    self.network = network
    self.bytes = bytes
  }
}

/// Start of every calendar bucket that overlaps `interval`, in order.
public func bucketStarts(in interval: DateInterval, by granularity: Granularity, calendar: Calendar) -> [Date] {
  guard let first = calendar.dateInterval(of: granularity.component, for: interval.start)?.start else { return [] }
  return Array(
    sequence(first: first) { calendar.date(byAdding: granularity.component, value: 1, to: $0) }
      .prefix { $0 < interval.end }
  )
}

/// Groups records into calendar buckets (local time, DST-aware), filling empty buckets with zero
/// so charts get a continuous axis.
public func aggregate(
  _ records: [UsageRecord],
  over interval: DateInterval,
  by granularity: Granularity,
  calendar: Calendar
) -> [UsagePoint] {
  let sums = records.reduce(into: [Date: ByteCounters]()) { sums, record in
    guard let start = calendar.dateInterval(of: granularity.component, for: record.bucket)?.start else { return }
    sums[start, default: .zero] = sums[start, default: .zero] + record.bytes
  }
  return bucketStarts(in: interval, by: granularity, calendar: calendar)
    .map { UsagePoint(date: $0, bytes: sums[$0] ?? .zero) }
}

/// Total usage per network, largest first.
public func usageByNetwork(_ records: [UsageRecord]) -> [NetworkUsage] {
  records
    .reduce(into: [String: ByteCounters]()) { $0[$1.network, default: .zero] = $0[$1.network, default: .zero] + $1.bytes }
    .map { NetworkUsage(network: $0.key, bytes: $0.value) }
    .sorted { ($0.bytes.total, $1.network) > ($1.bytes.total, $0.network) }
}

public func totalUsage(_ records: [UsageRecord]) -> ByteCounters {
  records.reduce(.zero) { $0 + $1.bytes }
}

/// The periods the dashboard's history chart can show.
public enum HistoryRange: String, CaseIterable, Identifiable, Sendable {
  case day = "24 Hours"
  case week = "7 Days"
  case month = "30 Days"
  case year = "12 Months"

  public var id: String { rawValue }

  public var granularity: Granularity {
    switch self {
    case .day: .hour
    case .week, .month: .day
    case .year: .month
    }
  }

  /// Whole buckets ending with the one that contains `now`: the last 24 hours, 7 or 30 days, or 12 months.
  public func interval(now: Date, calendar: Calendar) -> DateInterval {
    let component = granularity.component
    let count = switch self {
    case .day: 24
    case .week: 7
    case .month: 30
    case .year: 12
    }
    guard let current = calendar.dateInterval(of: component, for: now),
          let start = calendar.date(byAdding: component, value: -(count - 1), to: current.start)
    else { return DateInterval(start: now, duration: 0) }
    return DateInterval(start: start, end: current.end)
  }
}
