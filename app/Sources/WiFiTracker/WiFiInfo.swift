import AppKit
import CoreLocation
import CoreWLAN
import Observation
import WiFiTrackerCore

/// Reads connection identity alongside every counter sample. Network names can remain unavailable
/// even with authorization, so availability is separate from permission.
@MainActor
@Observable
final class WiFiInfo {
  enum Status: Equatable {
    case off, disconnected, connected
  }

  struct Snapshot: Equatable {
    var interfaceName: String?
    var ssid: String?
    var status: Status
    var locationAuthorization: CLAuthorizationStatus
    var locationServicesEnabled: Bool
  }

  private(set) var snapshot: Snapshot
  private(set) var connectionRevision = 0

  @ObservationIgnored private let client = CWWiFiClient.shared()
  @ObservationIgnored private let locationManager = CLLocationManager()
  @ObservationIgnored private let locationDelegate = LocationDelegate()
  @ObservationIgnored private let eventDelegate = WiFiEventDelegate()
  @ObservationIgnored private let snapshotReader: (() -> Snapshot)?

  init(snapshotReader: (() -> Snapshot)? = nil, monitorsEvents: Bool = true) {
    self.snapshotReader = snapshotReader
    snapshot = Snapshot(interfaceName: nil, ssid: nil, status: .off,
                        locationAuthorization: .notDetermined, locationServicesEnabled: false)
    locationManager.delegate = locationDelegate
    locationDelegate.onChange = { [weak self] in self?.refresh() }
    if monitorsEvents {
      client.delegate = eventDelegate
      eventDelegate.onChange = { [weak self] in
        guard let self else { return }
        self.connectionRevision += 1
        self.refresh()
      }
      for event in [CWEventType.ssidDidChange, .linkDidChange, .powerDidChange] {
        do {
          try client.startMonitoringEvent(with: event)
        } catch {
          NetworkDiagnostics.write("wifi-events-unavailable", fields: ["event": String(event.rawValue)])
        }
      }
    }
    refresh()
  }

  var interfaceName: String? { snapshot.interfaceName }
  var ssid: String? { snapshot.ssid }
  var status: Status { snapshot.status }
  var locationAuthorization: CLAuthorizationStatus { snapshot.locationAuthorization }
  var locationServicesEnabled: Bool { snapshot.locationServicesEnabled }
  var networkName: String { ssid ?? "Wi-Fi" }

  var networkIdentity: NetworkIdentity? {
    guard status == .connected else { return nil }
    return ssid.map(NetworkIdentity.named) ?? .unattributed
  }

  var hasLocationPermission: Bool {
    locationAuthorization == .authorizedAlways
  }

  var canReadNetworkNames: Bool { status == .connected && ssid != nil }

  var nameAvailabilityMessage: String? {
    // The actual name read establishes availability even when authorization metadata differs.
    if canReadNetworkNames { return nil }
    guard locationServicesEnabled else {
      return "Turn on Location Services in System Settings to split usage by network."
    }
    guard hasLocationPermission else {
      return "Allow Location access to split usage by network. Your location is never read."
    }
    guard status == .connected, ssid == nil else { return nil }
    return "Connected, but macOS has not provided the network name. Usage is counted as Unattributed Wi-Fi until the name is available."
  }

  var requestNamesButtonTitle: String {
    !locationServicesEnabled || !hasLocationPermission ? "Show network names…" : "Refresh network name"
  }

  var statusText: String {
    switch status {
    case .off: "Wi-Fi is off"
    case .disconnected: "Not connected"
    case .connected: "Connected · \(interfaceName ?? "Wi-Fi")"
    }
  }

  func refresh() {
    let next = snapshotReader?() ?? readSystemSnapshot()
    if next != snapshot {
      connectionRevision += 1
      snapshot = next
      NetworkDiagnostics.write("wifi-state", fields: diagnosticFields)
    }
  }

  var diagnosticFields: [String: String] {
    [
      "interface": interfaceName ?? "none",
      "connected": String(status == .connected),
      "powered": String(status != .off),
      "hasSSID": String(ssid != nil),
      "authorization": String(locationAuthorization.rawValue),
      "locationServicesEnabled": String(locationServicesEnabled),
      "connectionRevision": String(connectionRevision),
    ]
  }

  /// Request permission when needed, or retry a failed name read without changing network settings.
  func requestNetworkNames() {
    if locationServicesEnabled && locationAuthorization == .notDetermined {
      locationManager.requestWhenInUseAuthorization()
    } else if !locationServicesEnabled || !hasLocationPermission {
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
        NSWorkspace.shared.open(url)
      }
    } else {
      refresh()
    }
  }

  private func readSystemSnapshot() -> Snapshot {
    let interface = client.interface()
    let powered = interface?.powerOn() ?? false
    let name = powered ? interface?.ssid() : nil
    let connected = powered && (name != nil || (interface?.rssiValue() ?? 0) != 0)
    return Snapshot(
      interfaceName: interface?.interfaceName,
      ssid: name,
      status: !powered ? .off : connected ? .connected : .disconnected,
      locationAuthorization: locationManager.authorizationStatus,
      locationServicesEnabled: CLLocationManager.locationServicesEnabled()
    )
  }
}

@MainActor
private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
  var onChange: (() -> Void)?

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    Task { @MainActor in self.onChange?() }
  }
}

@MainActor
private final class WiFiEventDelegate: NSObject, CWEventDelegate {
  var onChange: (() -> Void)?

  nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
    Task { @MainActor in self.onChange?() }
  }

  nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
    Task { @MainActor in self.onChange?() }
  }

  nonisolated func powerStateDidChangeForWiFiInterface(withName interfaceName: String) {
    Task { @MainActor in self.onChange?() }
  }
}
