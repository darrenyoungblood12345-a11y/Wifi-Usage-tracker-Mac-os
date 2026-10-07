import SwiftUI
import WiFiTrackerCore

/// History for the selected range, loaded off the main thread from the store.
@MainActor
@Observable
final class HistoryModel {
  var range = HistoryRange.day
  private(set) var interval = HistoryRange.day.interval(now: .now, calendar: .current)
  private(set) var points: [UsagePoint] = []
  private(set) var networks: [NetworkUsage] = []
  private(set) var total = ByteCounters.zero

  func load(from store: UsageStore?) async {
    guard let store else { return }
    let range = range
    let calendar = Calendar.current
    let interval = range.interval(now: .now, calendar: calendar)
    let records = await Task.detached { (try? store.records(in: interval)) ?? [] }.value
    guard range == self.range else { return }
    self.interval = interval
    points = aggregate(records, over: interval, by: range.granularity, calendar: calendar)
    networks = usageByNetwork(records)
    total = totalUsage(records)
  }
}

enum LiveWindow: Int, CaseIterable, Identifiable {
  case oneMinute = 60
  case fiveMinutes = 300
  case fifteenMinutes = 900

  var id: Int { rawValue }

  var label: String {
    switch self {
    case .oneMinute: "1 min"
    case .fiveMinutes: "5 min"
    case .fifteenMinutes: "15 min"
    }
  }
}

struct DashboardView: View {
  @Environment(TrafficMonitor.self) private var monitor
  @AppStorage(SettingsKey.rateUnit) private var unit = RateUnit.bytes
  @AppStorage(SettingsKey.onboardingDismissed) private var onboardingDismissed = false
  @State private var history = HistoryModel()
  @AppStorage(SettingsKey.liveWindow) private var liveWindow = LiveWindow.fiveMinutes
  @State private var showsTable = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if !onboardingDismissed {
          OnboardingCard { onboardingDismissed = true }
        }
        header
        liveSection
        tiles
        historySection
      }
      .padding(24)
    }
    .frame(minWidth: 780, minHeight: 620)
    .background(Color(nsColor: .windowBackgroundColor))
    .navigationTitle("WiFi Tracker")
    .showsInDockWhileOpen()
    .task(id: "\(history.range.rawValue)-\(monitor.historyRevision)") {
      await history.load(from: monitor.store)
    }
    .task {
      await DevOptions.takeSnapshotIfRequested(monitor: monitor)
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 24) {
      NetworkHeading(wifi: monitor.wifi)
      Spacer()
      RateReadout(direction: .download, value: monitor.download, unit: unit)
        .frame(minWidth: 150, alignment: .leading)
      RateReadout(direction: .upload, value: monitor.upload, unit: unit)
        .frame(minWidth: 150, alignment: .leading)
    }
  }

  private var liveSection: some View {
    Card {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Live speed").font(.headline)
            Text("Peak today  ↓ \(formatRate(monitor.peakDownloadToday, unit: unit))  ↑ \(formatRate(monitor.peakUploadToday, unit: unit))")
              .font(.caption)
              .foregroundStyle(.secondary)
              .monospacedDigit()
          }
          Spacer()
          ChartLegend()
          Picker("Window", selection: $liveWindow) {
            ForEach(LiveWindow.allCases) { Text($0.label).tag($0) }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .fixedSize()
        }
        LiveChart(
          samples: monitor.samples.filter { $0.date > .now.addingTimeInterval(-Double(liveWindow.rawValue)) },
          unit: unit,
          window: Double(liveWindow.rawValue)
        )
        .frame(height: 200)
      }
    }
  }

  private var tiles: some View {
    HStack(spacing: 14) {
      StatTile(title: "Today", bytes: monitor.totals.today)
      StatTile(title: "This week", bytes: monitor.totals.week)
      StatTile(title: "This month", bytes: monitor.totals.month)
      StatTile(title: "All time", bytes: monitor.totals.allTime)
    }
  }

  private var historySection: some View {
    Card {
      VStack(alignment: .leading, spacing: 14) {
        HStack(alignment: .firstTextBaseline) {
          VStack(alignment: .leading, spacing: 3) {
            Text("Usage history").font(.headline)
            Text("\(formatBytes(history.total.total)) in the last \(history.range.rawValue.lowercased())")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
          Spacer()
          ChartLegend()
          Picker("Range", selection: $history.range) {
            ForEach(HistoryRange.allCases) { Text($0.rawValue).tag($0) }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .fixedSize()
          Toggle(isOn: $showsTable) {
            Image(systemName: "tablecells")
          }
          .toggleStyle(.button)
          .help("Show as table")
        }

        if showsTable {
          HistoryTable(points: history.points, range: history.range)
            .frame(height: 240)
        } else {
          HistoryChart(points: history.points, range: history.range, interval: history.interval)
            .frame(height: 240)
        }

        Divider()

        NetworksList(networks: history.networks, canReadNames: monitor.wifi.canReadNetworkNames) {
          monitor.wifi.requestNetworkNames()
        }
      }
    }
  }
}

/// Usage per Wi-Fi network for the selected range, as proportional stacked bars.
struct NetworksList: View {
  let networks: [NetworkUsage]
  let canReadNames: Bool
  let requestNames: () -> Void

  private var largest: Double { Double(networks.first?.bytes.total ?? 1) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Networks").font(.headline)
        Spacer()
        if !canReadNames {
          Button("Show network names…", action: requestNames)
            .buttonStyle(.link)
            .font(.callout)
        }
      }
      if networks.isEmpty {
        Text("Networks you use will appear here.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      ForEach(networks) { network in
        HStack(spacing: 14) {
          Text(network.network)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: 180, alignment: .leading)
          GeometryReader { geometry in
            let width = geometry.size.width * Double(network.bytes.total) / max(largest, 1)
            let downloadWidth = width * Double(network.bytes.received) / Double(max(network.bytes.total, 1))
            HStack(spacing: 2) {
              UnevenRoundedRectangle(bottomTrailingRadius: network.bytes.sent == 0 ? 4 : 0, topTrailingRadius: network.bytes.sent == 0 ? 4 : 0)
                .fill(Palette.download)
                .frame(width: max(0, downloadWidth - (network.bytes.sent > 0 ? 1 : 0)))
              if network.bytes.sent > 0 {
                UnevenRoundedRectangle(bottomTrailingRadius: 4, topTrailingRadius: 4)
                  .fill(Palette.upload)
                  .frame(width: max(2, width - downloadWidth - 1))
              }
            }
            .frame(height: 12)
            .frame(maxHeight: .infinity)
          }
          .frame(height: 20)
          Text(formatBytes(network.bytes.total))
            .monospacedDigit()
            .fontWeight(.medium)
            .frame(width: 80, alignment: .trailing)
          DirectionBreakdown(bytes: network.bytes, inline: true)
            .foregroundStyle(.secondary)
            .frame(width: 190, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
      }
    }
  }
}

struct OnboardingCard: View {
  @Environment(TrafficMonitor.self) private var monitor
  @State private var launchAtLogin = LoginItem.isEnabled
  @State private var loginError: String?
  let dismiss: () -> Void

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 14) {
        HStack {
          Text("Welcome to WiFi Tracker").font(.headline)
          Spacer()
          Button("Done", action: dismiss)
        }
        Text("Tracking has already started. Two optional extras:")
          .foregroundStyle(.secondary)

        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "location.circle").font(.title2).foregroundStyle(Color.accentColor)
          VStack(alignment: .leading, spacing: 3) {
            Text("Show network names").fontWeight(.medium)
            Text("macOS only shares the Wi-Fi name with apps that have Location access. WiFi Tracker uses it to split usage by network and never reads your location.")
              .font(.callout)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          Spacer()
          if monitor.wifi.canReadNetworkNames {
            Label("On", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
          } else {
            Button("Allow…") { monitor.wifi.requestNetworkNames() }
          }
        }

        HStack(alignment: .top, spacing: 12) {
          Image(systemName: "power.circle").font(.title2).foregroundStyle(Color.accentColor)
          VStack(alignment: .leading, spacing: 3) {
            Text("Open at login").fontWeight(.medium)
            Text(loginError ?? "Keep counting from the menu bar whenever your Mac is on.")
              .font(.callout)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Toggle("Open at login", isOn: $launchAtLogin)
            .labelsHidden()
            .toggleStyle(.switch)
            .onChange(of: launchAtLogin) { _, enabled in
              do {
                try LoginItem.setEnabled(enabled)
                loginError = nil
              } catch {
                loginError = "Couldn’t change this: \(error.localizedDescription)"
                launchAtLogin = LoginItem.isEnabled
              }
            }
        }
      }
    }
  }
}
