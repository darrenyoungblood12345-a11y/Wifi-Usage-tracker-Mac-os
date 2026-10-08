import Foundation

/// Opt-in, local JSON lines for tracking timing/availability. Never includes SSIDs or location fixes.
enum NetworkDiagnostics {
  static let enabled = ProcessInfo.processInfo.environment["WIFITRACKER_DIAGNOSTICS"] == "1"

  static func write(_ event: String, fields: [String: String] = [:]) {
    guard enabled else { return }
    let payload = fields.merging([
      "event": event,
      "date": ISO8601DateFormatter().string(from: .now),
      "uptime": String(ProcessInfo.processInfo.systemUptime),
    ]) { _, new in new }
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: .sortedKeys) else { return }
    try? FileHandle.standardError.write(contentsOf: data + Data([10]))
  }
}
