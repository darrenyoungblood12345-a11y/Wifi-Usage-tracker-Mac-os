import AppKit
import CoreLocation
import CoreWLAN
import Observation

/// The Wi-Fi interface and the network it's joined to.
///
/// macOS only reveals the network name (SSID) to apps with Location Services access, so until the
/// user allows it every network is recorded under `genericName`. The app never asks for a location fix.
@MainActor
@Observable
final class WiFiInfo {
  enum Status: Equatable {
    case off, disconnected, connected
  }

  static let genericName = "Wi-Fi"

  private(set) var interfaceName = "en0"
  private(set) var ssid: String?
  private(set) var status = Status.disconnected
  private(set) var locationAuthorization: CLAuthorizationStatus

  @ObservationIgnored private let client = CWWiFiClient.shared()
  @ObservationIgnored private let locationManager = CLLocationManager()
  @ObservationIgnored private let locationDelegate = LocationDelegate()
  @ObservationIgnored private var lastRefresh: ContinuousClock.Instant?

  init() {
    locationAuthorization = locationManager.authorizationStatus
    locationManager.delegate = locationDelegate
    locationDelegate.onChange = { [weak self] status in
      self?.locationAuthorization = status
      self?.refresh()
    }
    refresh()
  }

  /// The name usage is recorded under.
  var networkName: String { ssid ?? Self.genericName }

  var canReadNetworkNames: Bool {
    switch locationAuthorization {
    case .notDetermined, .denied, .restricted: false
    default: true
    }
  }

  var statusText: String {
    switch status {
    case .off: "Wi-Fi is off"
    case .disconnected: "Not connected"
    case .connected: "Connected · \(interfaceName)"
    }
  }

  /// Re-reads the interface at most every five seconds; cheap enough to call on every sample.
  func refreshIfStale() {
    guard let lastRefresh, ContinuousClock.now - lastRefresh < .seconds(5) else {
      refresh()
      return
    }
  }

  func refresh() {
    lastRefresh = .now
    guard let interface = client.interface() else {
      status = .off
      ssid = nil
      return
    }
    interfaceName = interface.interfaceName ?? "en0"
    guard interface.powerOn() else {
      status = .off
      ssid = nil
      return
    }
    ssid = interface.ssid()
    status = ssid != nil || interface.rssiValue() != 0 ? .connected : .disconnected
  }

  /// Shows the system prompt, or opens Location Services settings if the user already said no.
  func requestNetworkNames() {
    switch locationAuthorization {
    case .notDetermined:
      locationManager.requestWhenInUseAuthorization()
    default:
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
        NSWorkspace.shared.open(url)
      }
    }
  }
}

@MainActor
private final class LocationDelegate: NSObject, CLLocationManagerDelegate {
  var onChange: ((CLAuthorizationStatus) -> Void)?

  nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    let status = manager.authorizationStatus
    Task { @MainActor in self.onChange?(status) }
  }
}
