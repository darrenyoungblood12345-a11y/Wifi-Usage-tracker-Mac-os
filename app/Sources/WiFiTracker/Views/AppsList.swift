import AppKit
import SwiftUI
import WiFiTrackerCore

/// Saved per-app usage and total Wi-Fi usage for a range, loaded off the main thread from the store.
@MainActor
@Observable
final class AppUsageModel {
  private(set) var apps: [AppUsage] = []
  private(set) var wifiTotal = ByteCounters.zero

  func load(_ range: HistoryRange, from store: UsageStore?) async {
    guard let store else { return }
    let interval = range.interval(now: .now, calendar: .current)
    let (apps, wifiTotal) = await Task.detached {
      ((try? store.appUsage(in: interval)) ?? [], (try? store.total(since: interval.start)) ?? .zero)
    }.value
    guard !Task.isCancelled else { return }
    self.apps = apps
    self.wifiTotal = wifiTotal
  }
}

/// Wi-Fi usage per app for the chosen range, largest first, with each app's live speed.
struct AppsSection: View {
  @Environment(TrafficMonitor.self) private var monitor
  @AppStorage(SettingsKey.rateUnit) private var unit = RateUnit.bytes
  @AppStorage(SettingsKey.appsRange) private var range = HistoryRange.day
  @State private var model = AppUsageModel()
  @State private var showsAll = false

  private static let collapsedCount = 10

  var body: some View {
    let list = appUsageList(stored: model.apps, pending: monitor.apps.pendingUsage, wifiTotal: model.wifiTotal)
    let apps = list.filter { !$0.isOther }
    let other = list.filter(\.isOther)
    let visible = (showsAll ? apps : Array(apps.prefix(Self.collapsedCount))) + other
    let largest = Double(list.map(\.bytes.total).max() ?? 1)

    Card {
      VStack(alignment: .leading, spacing: 12) {
        header(appCount: apps.count, total: list.reduce(.zero) { $0 + $1.bytes })
        if let reason = monitor.apps.unavailableReason {
          Label(reason, systemImage: "exclamationmark.triangle")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        if list.isEmpty {
          Text("Apps using Wi-Fi will appear here.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        VStack(spacing: 4) {
          ForEach(visible) { app in
            AppUsageRow(app: app, rate: monitor.apps.rates[app.id], largest: largest, unit: unit)
          }
        }
        if apps.count > Self.collapsedCount {
          Button(showsAll ? "Show fewer" : "Show all \(apps.count) apps") { showsAll.toggle() }
            .buttonStyle(.link)
            .font(.callout)
        }
      }
    }
    .task(id: "\(range.rawValue)-\(monitor.historyRevision)") {
      await model.load(range, from: monitor.store)
    }
  }

  private func header(appCount: Int, total: ByteCounters) -> some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Apps").font(.headline)
        Text("\(appCount) \(appCount == 1 ? "app" : "apps") · \(formatBytes(total.total)) in the last \(range.rawValue.lowercased())")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Picker("Range", selection: $range) {
        ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .fixedSize()
    }
  }
}

/// One app: icon, name and live speed, then its share as a bar, its total and the split by direction.
struct AppUsageRow: View {
  let app: AppUsage
  let rate: AppRate?
  let largest: Double
  let unit: RateUnit

  var body: some View {
    HStack(spacing: 14) {
      HStack(spacing: 10) {
        AppIconView(app: app)
        VStack(alignment: .leading, spacing: 1) {
          Text(app.name)
            .lineLimit(1)
            .truncationMode(.tail)
          if let rateText {
            Text(rateText)
              .font(.caption)
              .foregroundStyle(.secondary)
              .monospacedDigit()
              .lineLimit(1)
          }
        }
      }
      // Fixed height so rows don't jump as apps start and stop.
      .frame(width: 200, height: 34, alignment: .leading)
      UsageBar(bytes: app.bytes, largest: largest)
      Text(formatBytes(app.bytes.total))
        .monospacedDigit()
        .fontWeight(.medium)
        .frame(width: 80, alignment: .trailing)
      DirectionBreakdown(bytes: app.bytes, inline: true)
        .foregroundStyle(.secondary)
        .frame(width: 190, alignment: .trailing)
    }
    .accessibilityElement(children: .combine)
    .help(app.isOther
      ? "Wi-Fi traffic not tied to an app: packet headers (apps are measured by the data they send and receive), connections that closed between samples, and traffic from before per-app tracking started or while WiFi Tracker was closed."
      : "")
  }

  private var rateText: String? {
    guard let rate, rate.download + rate.upload > 0 else { return nil }
    return "↓ \(formatRate(rate.download, unit: unit))  ↑ \(formatRate(rate.upload, unit: unit))"
  }
}

private struct AppIconView: View {
  let app: AppUsage

  var body: some View {
    if let icon = AppIcons.icon(for: app) {
      Image(nsImage: icon)
        .resizable()
        .frame(width: 22, height: 22)
    } else {
      Image(systemName: app.isOther ? "ellipsis.circle" : "gearshape")
        .font(.system(size: 15))
        .foregroundStyle(.secondary)
        .frame(width: 22, height: 22)
    }
  }
}

/// App icons by bundle identifier (or bundle path), looked up once each.
@MainActor
enum AppIcons {
  private static var cache: [String: NSImage?] = [:]

  static func icon(for app: AppUsage) -> NSImage? {
    guard !app.isOther else { return nil }
    if let cached = cache[app.id] { return cached }
    let url = app.id.hasPrefix("/")
      ? URL(fileURLWithPath: app.id)
      : NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.id)
    let icon = url.map { NSWorkspace.shared.icon(forFile: $0.path) }
    cache[app.id] = icon
    return icon
  }
}
