import AppKit
import SwiftUI
import WiFiTrackerCore

/// Environment overrides for development and for producing website screenshots. Inert in normal use.
enum DevOptions {
  private static let environment = ProcessInfo.processInfo.environment

  /// `WIFITRACKER_STORE=/path/usage.sqlite` points the app at a different database.
  static var storeURL: URL {
    environment["WIFITRACKER_STORE"].map { URL(fileURLWithPath: $0) } ?? UsageStore.defaultURL
  }

  /// `WIFITRACKER_SNAPSHOT=/path/dashboard.png` opens the dashboard, saves it as a PNG after
  /// `WIFITRACKER_SNAPSHOT_DELAY` seconds (default 8), then quits. The app renders its own window,
  /// so no Screen Recording permission is needed.
  static var snapshotPath: String? { environment["WIFITRACKER_SNAPSHOT"] }

  /// Snapshots ignore the pointer so a stray cursor doesn't leave a tooltip in the picture.
  static var isSnapshotting: Bool { snapshotPath != nil }

  /// `WIFITRACKER_APPEARANCE=light|dark` forces an appearance (for snapshots of each theme).
  @MainActor
  static func applyAppearance() {
    switch environment["WIFITRACKER_APPEARANCE"] {
    case "light": NSApp.appearance = NSAppearance(named: .aqua)
    case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
    default: break
    }
  }

  @MainActor private static var hasStartedSnapshot = false

  /// Renders the full dashboard in an off-screen window (on-screen windows can't be taller than the display).
  @MainActor
  static func takeSnapshotIfRequested(monitor: TrafficMonitor) async {
    guard let snapshotPath, !hasStartedSnapshot else { return }
    hasStartedSnapshot = true
    let delay = Double(environment["WIFITRACKER_SNAPSHOT_DELAY"] ?? "") ?? 8
    try? await Task.sleep(for: .seconds(delay))

    let height = Double(environment["WIFITRACKER_SNAPSHOT_HEIGHT"] ?? "") ?? 1060
    let host = NSHostingView(rootView: DashboardView().environment(monitor))
    let window = NSWindow(
      contentRect: NSRect(x: -20_000, y: -20_000, width: 980, height: height),
      styleMask: [.borderless], backing: .buffered, defer: false
    )
    window.appearance = NSApp.effectiveAppearance
    window.contentView = host
    window.orderFrontRegardless()
    try? await Task.sleep(for: .seconds(2))

    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
      host.cacheDisplay(in: host.bounds, to: bitmap)
      try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: snapshotPath))
    }
    savePopoverSnapshot(monitor: monitor, appearance: window.effectiveAppearance)
    NSApp.terminate(nil)
  }

  /// Renders the menu bar popover next to the dashboard snapshot (`…-popover.png`).
  @MainActor
  private static func savePopoverSnapshot(monitor: TrafficMonitor, appearance: NSAppearance) {
    guard let snapshotPath else { return }
    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    let renderer = ImageRenderer(
      content: MenuBarPopover()
        .environment(monitor)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, isDark ? .dark : .light)
    )
    renderer.scale = 2
    let url = URL(fileURLWithPath: snapshotPath).deletingPathExtension().appendingPathExtension("popover.png")
    appearance.performAsCurrentDrawingAppearance {
      guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
            let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return }
      try? png.write(to: url)
    }
  }
}
