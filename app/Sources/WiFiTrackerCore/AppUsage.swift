import Foundation

/// Wi-Fi bytes attributed to one app (or background process) over some period.
public struct AppUsage: Equatable, Identifiable, Sendable {
  /// Bundle identifier for apps, executable name for other processes, or `AppUsage.otherID`.
  public var id: String
  public var name: String
  public var bytes: ByteCounters

  public init(id: String, name: String, bytes: ByteCounters) {
    self.id = id
    self.name = name
    self.bytes = bytes
  }

  /// Wi-Fi traffic no app accounts for: packet headers (the interface counts them, sockets don't),
  /// connections that closed between samples, and traffic from before per-app tracking started or
  /// while the app was closed.
  public static let otherID = ""
  public static let otherName = "Other traffic"

  public var isOther: Bool { id == Self.otherID }
}

/// Bytes one app moved during one hour.
public struct AppUsageRecord: Equatable, Sendable {
  public var bucket: Date
  public var app: String
  public var name: String
  public var bytes: ByteCounters

  public init(bucket: Date, app: String, name: String, bytes: ByteCounters) {
    self.bucket = bucket
    self.app = app
    self.name = name
    self.bytes = bytes
  }
}

/// Start of the hour containing `date`, which is the granularity per-app usage is stored at.
public func hourBucket(for date: Date) -> Date {
  Date(timeIntervalSince1970: (date.timeIntervalSince1970 / 3600).rounded(.down) * 3600)
}

/// The Apps list: saved plus not-yet-saved usage per app, largest first, then the Wi-Fi traffic
/// the saved app usage doesn't account for as "Other traffic".
public func appUsageList(stored: [AppUsage], pending: [AppUsage], wifiTotal: ByteCounters) -> [AppUsage] {
  let apps = (stored + pending)
    .reduce(into: [String: AppUsage]()) { merged, usage in
      let bytes = (merged[usage.id]?.bytes ?? .zero) + usage.bytes
      merged[usage.id] = AppUsage(id: usage.id, name: usage.name, bytes: bytes)
    }
    .values
    .sorted { ($0.bytes.total, $1.name) > ($1.bytes.total, $0.name) }
  let other = unattributed(wifi: wifiTotal, apps: stored.reduce(.zero) { $0 + $1.bytes })
  return other.total > 0 ? apps + [AppUsage(id: AppUsage.otherID, name: AppUsage.otherName, bytes: other)] : apps
}

/// Wi-Fi bytes left over after the apps' share, per direction and never negative.
public func unattributed(wifi: ByteCounters, apps: ByteCounters) -> ByteCounters {
  ByteCounters(
    received: wifi.received > apps.received ? wifi.received - apps.received : 0,
    sent: wifi.sent > apps.sent ? wifi.sent - apps.sent : 0
  )
}
