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

/// Start of the calendar hour containing `date`, which is the granularity per-app usage is stored at.
///
/// Calendar hours rather than UTC ones, so a bucket never starts before the local day or month
/// its traffic happened in: history ranges start at local midnight, which in a time zone such as
/// UTC+5:30 falls in the middle of a UTC hour.
public func hourBucket(for date: Date, calendar: Calendar = .current) -> Date {
  calendar.dateInterval(of: .hour, for: date)?.start ?? date
}

/// The Apps list: saved plus not-yet-saved usage per app, largest first, then the Wi-Fi traffic
/// none of it accounts for as "Other traffic".
///
/// `wifiTotal` has to cover saved and not-yet-saved traffic alike. Other is what is left after
/// every app in the list: unsaved app usage may already be in the saved Wi-Fi total (an app save
/// that failed after its Wi-Fi save), and taking off saved usage only would list it twice.
public func appUsageList(stored: [AppUsage], pending: [AppUsage], wifiTotal: ByteCounters) -> [AppUsage] {
  let apps = (stored + pending)
    .reduce(into: [String: AppUsage]()) { merged, usage in
      let bytes = (merged[usage.id]?.bytes ?? .zero) + usage.bytes
      merged[usage.id] = AppUsage(id: usage.id, name: usage.name, bytes: bytes)
    }
    .values
    .sorted { ($0.bytes.total, $1.name) > ($1.bytes.total, $0.name) }
  let other = unattributed(wifi: wifiTotal, apps: apps.reduce(.zero) { $0 + $1.bytes })
  return other.total > 0 ? apps + [AppUsage(id: AppUsage.otherID, name: AppUsage.otherName, bytes: other)] : apps
}

/// Wi-Fi bytes left over after the apps' share, per direction and never negative.
public func unattributed(wifi: ByteCounters, apps: ByteCounters) -> ByteCounters {
  ByteCounters(
    received: wifi.received > apps.received ? wifi.received - apps.received : 0,
    sent: wifi.sent > apps.sent ? wifi.sent - apps.sent : 0
  )
}
