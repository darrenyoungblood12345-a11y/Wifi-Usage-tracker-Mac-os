import AppKit
import ServiceManagement
import SwiftUI
import WiFiTrackerCore

/// Series colors, validated as a colorblind-safe pair in both appearances.
enum Palette {
  static let download = Color(light: 0x2A78D6, dark: 0x3987E5)
  static let upload = Color(light: 0xEB6834, dark: 0xD95926)
  static let gridline = Color(light: 0xE1E0D9, dark: 0x2C2C2A)
  static let cardBorder = Color.primary.opacity(0.08)

  static let seriesScale: KeyValuePairs<String, Color> = [
    Direction.download.rawValue: download,
    Direction.upload.rawValue: upload,
  ]
}

enum Direction: String, CaseIterable, Identifiable {
  case download = "Download"
  case upload = "Upload"

  var id: String { rawValue }
  var color: Color { self == .download ? Palette.download : Palette.upload }
  var symbol: String { self == .download ? "arrow.down" : "arrow.up" }
}

extension Color {
  init(light: UInt32, dark: UInt32) {
    self.init(nsColor: NSColor(name: nil) { appearance in
      let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
      return NSColor(hex: isDark ? dark : light)
    })
  }
}

extension NSColor {
  convenience init(hex: UInt32) {
    self.init(
      srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
      green: CGFloat((hex >> 8) & 0xFF) / 255,
      blue: CGFloat(hex & 0xFF) / 255,
      alpha: 1
    )
  }
}

/// What the menu bar item shows.
enum MenuBarStyle: String, CaseIterable, Identifiable {
  case both, combined, iconOnly

  var id: String { rawValue }

  var label: String {
    switch self {
    case .both: "Download and upload"
    case .combined: "Combined speed"
    case .iconOnly: "Icon only"
    }
  }
}

enum SettingsKey {
  static let rateUnit = "rateUnit"
  static let menuBarStyle = "menuBarStyle"
  static let onboardingDismissed = "onboardingDismissed"
  static let hasLaunchedBefore = "hasLaunchedBefore"
  static let liveWindow = "liveWindow"
}

enum LoginItem {
  static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

  static func setEnabled(_ enabled: Bool) throws {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
  }
}

/// Downsamples by averaging consecutive runs so charts stay light (≤ `limit` points).
func downsample(_ samples: [RateSample], limit: Int) -> [RateSample] {
  guard samples.count > limit, limit > 0 else { return samples }
  let size = Int((Double(samples.count) / Double(limit)).rounded(.up))
  return stride(from: 0, to: samples.count, by: size).map { start in
    let run = samples[start..<min(start + size, samples.count)]
    let count = Double(run.count)
    return RateSample(
      date: run.last!.date,
      download: run.reduce(0) { $0 + $1.download } / count,
      upload: run.reduce(0) { $0 + $1.upload } / count
    )
  }
}

/// Pads a short rate string with figure spaces so the menu bar item doesn't jitter in width.
func padded(_ text: String, to width: Int) -> String {
  String(repeating: "\u{2007}", count: max(0, width - text.count)) + text
}
