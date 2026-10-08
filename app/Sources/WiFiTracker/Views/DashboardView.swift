import SwiftUI
import WiFiTrackerCore

/// Combines the last saved snapshot with live traffic and commits made after that snapshot.
@MainActor
@Observable
final class HistoryModel {
  var range = HistoryRange.day
  private(set) var interval = HistoryRange.day.interval(now: .now, calendar: .current)
  private(set) var points: [UsagePoint] = []
  private(set) var networks: [NetworkUsage] = []
  private(set) var total = ByteCounters.zero
  private(set) var loadError: String?

  @ObservationIgnored private var snapshots: [HistoryRange: Snapshot] = [:]
  @ObservationIgnored private var pendingRecords: [UsageRecord] = []
  @ObservationIgnored private var committedRecords: [UsageRecord] = []
  @ObservationIgnored private var revision = 0
  @ObservationIgnored private var epoch: Int?
  @ObservationIgnored private var request = 0
  @ObservationIgnored private var calendar = Calendar.current

  private struct RecordKey: Hashable {
    let bucket: Date
    let identity: NetworkIdentity

    init(_ record: UsageRecord) {
      bucket = record.bucket
      identity = record.identity
    }
  }

  private struct Snapshot {
    let records: [UsageRecord]
    let committedBaseline: [RecordKey: ByteCounters]
    let interval: DateInterval
    let points: [UsagePoint]
    let networks: [NetworkUsage]
    let total: ByteCounters

    init(records: [UsageRecord], committedBaseline: [RecordKey: ByteCounters], interval: DateInterval, range: HistoryRange, calendar: Calendar) {
      self.records = records
      self.committedBaseline = committedBaseline
      self.interval = interval
      let visible = records.filter { $0.bucket >= interval.start && $0.bucket < interval.end }
      points = aggregate(visible, over: interval, by: range.granularity, calendar: calendar)
      networks = usageByNetwork(visible)
      total = totalUsage(visible)
    }
  }

  func updateLive(
    pending: [UsageRecord],
    committed: [UsageRecord],
    revision: Int,
    epoch: Int,
    now: Date = .now,
    calendar: Calendar = .current
  ) {
    if let previousEpoch = self.epoch, previousEpoch != epoch {
      snapshots = [:]
      loadError = nil
      request += 1
    }
    self.epoch = epoch
    self.revision = revision
    self.calendar = calendar
    interval = range.interval(now: now, calendar: calendar)
    pendingRecords = pending
    committedRecords = committed
    rebuild()
  }

  func load(from store: UsageStore?, isCurrent: () -> Bool) async {
    guard let store else { return }
    await load(records: { interval in
      try await Task.detached { try store.records(in: interval) }.value
    }, isCurrent: isCurrent)
  }

  /// A revision check also covers writes that occur before SwiftUI delivers its change callbacks.
  func load(
    records read: @Sendable (DateInterval) async throws -> [UsageRecord],
    isCurrent: () -> Bool = { true }
  ) async {
    request += 1
    let request = request
    let range = range
    let interval = interval
    let revision = revision
    let epoch = epoch
    let baseline = sums(committedRecords)
    let started = ProcessInfo.processInfo.systemUptime
    var outcome = "discarded"
    var recordCount = 0
    defer {
      NetworkDiagnostics.write("history-load", fields: [
        "outcome": outcome,
        "range": range.rawValue,
        "revision": String(revision),
        "epoch": String(epoch ?? 0),
        "records": String(recordCount),
        "elapsedMilliseconds": String((ProcessInfo.processInfo.systemUptime - started) * 1_000),
      ])
    }
    do {
      let records = try await read(interval)
      recordCount = records.count
      guard !Task.isCancelled, request == self.request, range == self.range,
            revision == self.revision, epoch == self.epoch, isCurrent() else { return }
      snapshots[range] = Snapshot(records: records, committedBaseline: baseline, interval: interval, range: range, calendar: calendar)
      outcome = "success"
      loadError = nil
      rebuild()
    } catch {
      guard !Task.isCancelled, request == self.request, range == self.range,
            revision == self.revision, epoch == self.epoch, isCurrent() else { return }
      outcome = "error"
      loadError = "Couldn’t read saved usage: \(error.localizedDescription)"
    }
  }

  private func sums(_ records: [UsageRecord]) -> [RecordKey: ByteCounters] {
    records.reduce(into: [:]) { $0[RecordKey($1), default: .zero] += $1.bytes }
  }

  private func rebuild() {
    if let snapshot = snapshots[range], snapshot.interval != interval {
      snapshots[range] = Snapshot(records: snapshot.records, committedBaseline: snapshot.committedBaseline, interval: interval, range: range, calendar: calendar)
    }
    let snapshot = snapshots[range]
    let baseline = snapshot?.committedBaseline ?? [:]
    // These cumulative commits stay visible while the next SQLite read is in flight.
    // Subtract only the commits known to be included in the saved snapshot.
    let committedDelta = sums(committedRecords).compactMap { key, current -> UsageRecord? in
      let previous = baseline[key] ?? .zero
      let delta = ByteCounters(
        received: current.received - min(current.received, previous.received),
        sent: current.sent - min(current.sent, previous.sent)
      )
      guard delta.total > 0 else { return nil }
      return UsageRecord(bucket: key.bucket, network: key.identity.storageName, bytes: delta, isUnattributed: key.identity.isUnattributed)
    }
    let live = (committedDelta + pendingRecords).filter { $0.bucket >= interval.start && $0.bucket < interval.end }
    let savedPoints = snapshot?.points ?? aggregate([], over: interval, by: range.granularity, calendar: calendar)
    let livePoints = aggregate(live, over: interval, by: range.granularity, calendar: calendar)
    points = zip(savedPoints, livePoints).map { UsagePoint(date: $0.date, bytes: $0.bytes + $1.bytes) }
    let savedNetworks = (snapshot?.networks ?? []).map {
      UsageRecord(bucket: interval.start, network: $0.network, bytes: $0.bytes, isUnattributed: $0.isUnattributed)
    }
    networks = usageByNetwork(savedNetworks + live)
    total = (snapshot?.total ?? .zero) + totalUsage(live)
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
  @State private var didRefreshPresentation = false
  @AppStorage(SettingsKey.liveWindow) private var liveWindow = LiveWindow.fiveMinutes
  @State private var showsTable = false

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        if !onboardingDismissed {
          OnboardingCard { onboardingDismissed = true }
        }
        header
        if let error = monitor.storeError {
          storageErrorCard(error)
        }
        liveSection
        tiles
        historySection
        AppsSection()
      }
      .padding(24)
    }
    .frame(minWidth: 780, minHeight: 620)
    .background(Color(nsColor: .windowBackgroundColor))
    .navigationTitle("WiFi Tracker")
    .showsInDockWhileOpen()
    .task(id: "\(history.range.rawValue)-\(monitor.historyRevision)-\(monitor.historyEpoch)") {
      if !didRefreshPresentation {
        didRefreshPresentation = true
        monitor.refreshForPresentation()
      }
      updateHistoryLive()
      let revision = monitor.historyRevision
      let epoch = monitor.historyEpoch
      await history.load(from: monitor.store) {
        monitor.historyRevision == revision && monitor.historyEpoch == epoch
      }
    }
    .onChange(of: monitor.pendingRecords) { _, _ in
      updateHistoryLive()
    }
    .onChange(of: monitor.committedRecords) { _, _ in
      updateHistoryLive()
    }
    .onChange(of: monitor.historyEpoch) { _, _ in
      updateHistoryLive()
    }
    .task {
      await DevOptions.takeSnapshotIfRequested(monitor: monitor)
    }
  }

  private func updateHistoryLive() {
    history.updateLive(
      pending: monitor.pendingRecords,
      committed: monitor.committedRecords,
      revision: monitor.historyRevision,
      epoch: monitor.historyEpoch
    )
  }

  private func storageErrorCard(_ error: String) -> some View {
    Card {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
        VStack(alignment: .leading, spacing: 4) {
          Text("Usage storage needs attention").font(.headline)
          Text(error).font(.callout).foregroundStyle(.secondary)
          Text("Live traffic remains visible. Some history updates may be incomplete.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        if monitor.store != nil {
          Button("Retry") {
            monitor.refreshForPresentation()
            monitor.flush()
          }
        }
      }
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

        if let error = history.loadError {
          HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
              Label("Showing the last available history and live traffic", systemImage: "exclamationmark.triangle")
                .font(.callout)
              Text(error).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Retry") { monitor.refreshForPresentation() }
          }
        }

        if showsTable {
          HistoryTable(points: history.points, range: history.range)
            .frame(height: 240)
        } else {
          HistoryChart(points: history.points, range: history.range, interval: history.interval)
            .frame(height: 240)
        }

        Divider()

        NetworksList(
          networks: history.networks,
          nameAvailabilityMessage: monitor.wifi.nameAvailabilityMessage,
          requestNamesButtonTitle: monitor.wifi.requestNamesButtonTitle
        ) {
          monitor.wifi.requestNetworkNames()
        }
      }
    }
  }
}

/// Usage per Wi-Fi network for the selected range, as proportional stacked bars.
struct NetworksList: View {
  let networks: [NetworkUsage]
  let nameAvailabilityMessage: String?
  let requestNamesButtonTitle: String
  let requestNames: () -> Void

  private var largest: Double { Double(networks.first?.bytes.total ?? 1) }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text("Networks").font(.headline)
        Spacer()
        if nameAvailabilityMessage != nil {
          Button(requestNamesButtonTitle, action: requestNames)
            .buttonStyle(.link)
            .font(.callout)
        }
      }
      if let message = nameAvailabilityMessage {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if networks.isEmpty {
        Text("Networks you use will appear here.")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
      ForEach(networks) { network in
        VStack(alignment: .leading, spacing: 4) {
          HStack(spacing: 14) {
            Text(network.displayName)
              .lineLimit(1)
              .truncationMode(.tail)
              .frame(width: 180, alignment: .leading)
            UsageBar(bytes: network.bytes, largest: largest)
            Text(formatBytes(network.bytes.total))
              .monospacedDigit()
              .fontWeight(.medium)
              .frame(width: 80, alignment: .trailing)
            DirectionBreakdown(bytes: network.bytes, inline: true)
              .foregroundStyle(.secondary)
              .frame(width: 190, alignment: .trailing)
          }
          .accessibilityElement(children: .combine)
          if network.isUnattributed {
            Text("Traffic counted when its Wi-Fi network could not be confirmed.")
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
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
          if monitor.wifi.hasLocationPermission && monitor.wifi.locationServicesEnabled {
            Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
          } else {
            Button(monitor.wifi.requestNamesButtonTitle) { monitor.wifi.requestNetworkNames() }
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
