import SwiftUI
import WiFiTrackerCore

struct MenuBarLabel: View {
  @Environment(TrafficMonitor.self) private var monitor
  @Environment(\.openWindow) private var openWindow
  @AppStorage(SettingsKey.rateUnit) private var unit = RateUnit.bytes
  @AppStorage(SettingsKey.menuBarStyle) private var style = MenuBarStyle.both
  @AppStorage(SettingsKey.hasLaunchedBefore) private var hasLaunchedBefore = false

  var body: some View {
    content
      .task {
        guard !hasLaunchedBefore || DevOptions.snapshotPath != nil else { return }
        hasLaunchedBefore = true
        openWindow(id: WindowID.dashboard)
      }
  }

  @ViewBuilder private var content: some View {
    switch style {
    case .both:
      Text("↓\(padded(formatRate(monitor.download, unit: unit), to: 9)) ↑\(padded(formatRate(monitor.upload, unit: unit), to: 9))")
        .monospacedDigit()
    case .combined:
      Text("⇅\(padded(formatRate(monitor.download + monitor.upload, unit: unit), to: 9))")
        .monospacedDigit()
    case .iconOnly:
      Image(systemName: monitor.wifi.status == .off ? "wifi.slash" : "wifi")
    }
  }
}

struct MenuBarPopover: View {
  @Environment(TrafficMonitor.self) private var monitor
  @Environment(\.openWindow) private var openWindow
  @Environment(\.openSettings) private var openSettings
  @Environment(\.dismiss) private var dismiss
  @AppStorage(SettingsKey.rateUnit) private var unit = RateUnit.bytes

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      NetworkHeading(wifi: monitor.wifi, compact: true)

      HStack(alignment: .firstTextBaseline) {
        RateReadout(direction: .download, value: monitor.download, unit: unit, size: 22)
        Spacer()
        RateReadout(direction: .upload, value: monitor.upload, unit: unit, size: 22)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Last minute")
          .font(.caption)
          .foregroundStyle(.secondary)
        LiveChart(samples: Array(monitor.samples.suffix(60)), unit: unit, compact: true)
          .frame(height: 70)
      }

      Divider()

      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("Used today")
            .font(.caption)
            .foregroundStyle(.secondary)
          Text(formatBytes(monitor.totals.today.total))
            .font(.title3.weight(.semibold))
        }
        Spacer()
        DirectionBreakdown(bytes: monitor.totals.today)
      }

      Divider()

      if let error = monitor.storeError {
        Label(error, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(spacing: 2) {
        MenuRow(title: "Open Dashboard", systemImage: "chart.bar.xaxis") {
          openWindow(id: WindowID.dashboard)
          NSApp.activate()
          dismiss()
        }
        MenuRow(title: "Settings…", systemImage: "gearshape") {
          openSettings()
          NSApp.activate()
          dismiss()
        }
        MenuRow(title: "Quit WiFi Tracker", systemImage: "power") {
          NSApp.terminate(nil)
        }
      }
    }
    .padding(16)
    .frame(width: 320)
  }
}

private struct MenuRow: View {
  let title: String
  let systemImage: String
  let action: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: systemImage)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .background(isHovered ? Color.primary.opacity(0.08) : .clear, in: RoundedRectangle(cornerRadius: 6))
    .onHover { isHovered = $0 }
  }
}
