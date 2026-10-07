import Foundation

/// How speeds are shown: bytes per second (MB/s, like Finder) or bits per second (Mbps, like ISPs).
public enum RateUnit: String, CaseIterable, Identifiable, Sendable {
  case bytes, bits

  public var id: String { rawValue }

  public var label: String {
    switch self {
    case .bytes: "Bytes (MB/s)"
    case .bits: "Bits (Mbps)"
    }
  }
}

/// A byte count like Finder shows it: decimal units, about three significant digits.
/// `formatBytes(1_234_567_890)` → `"1.23 GB"`.
public func formatBytes(_ bytes: UInt64) -> String {
  guard bytes >= 1000 else { return "\(bytes) B" }
  return scaled(Double(bytes), units: ["KB", "MB", "GB", "TB", "PB"])
}

/// A transfer speed in the chosen unit, kept short enough for the menu bar.
/// `formatRate(1_250_000, unit: .bytes)` → `"1.25 MB/s"`; `.bits` → `"10.0 Mbps"`.
public func formatRate(_ bytesPerSecond: Double, unit: RateUnit) -> String {
  let value = max(0, bytesPerSecond)
  switch unit {
  case .bytes: return scaled(value, units: ["KB/s", "MB/s", "GB/s"], minimumUnit: true)
  case .bits: return scaled(value * 8, units: ["Kbps", "Mbps", "Gbps"], minimumUnit: true)
  }
}

/// Divides by 1000 into the first unit, then keeps dividing while the value is ≥ 1000.
/// With `minimumUnit`, tiny values stay in the first unit ("0.3 KB/s") rather than dropping to bytes.
private func scaled(_ value: Double, units: [String], minimumUnit: Bool = false) -> String {
  let (amount, unit) = units.dropFirst().reduce((value / 1000, units[0])) { current, next in
    current.0 >= 999.5 ? (current.0 / 1000, next) : current
  }
  if minimumUnit && amount < 0.05 { return "0 \(unit)" }
  return "\(threeSignificantDigits(amount)) \(unit)"
}

private func threeSignificantDigits(_ value: Double) -> String {
  switch value {
  case ..<9.995: String(format: "%.2f", value)
  case ..<99.95: String(format: "%.1f", value)
  default: String(format: "%.0f", value)
  }
}
