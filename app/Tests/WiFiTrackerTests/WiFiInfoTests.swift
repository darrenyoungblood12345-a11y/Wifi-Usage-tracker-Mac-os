import CoreLocation
import Testing
import WiFiTrackerCore
@testable import WiFiTracker

@Suite("Network name availability")
@MainActor
struct WiFiInfoTests {
  @Test("authorization alone does not claim a readable network name")
  func unavailableSSID() {
    let wifi = makeWiFi(ssid: nil)
    #expect(wifi.hasLocationPermission)
    #expect(!wifi.canReadNetworkNames)
    #expect(wifi.networkIdentity == .unattributed)
    #expect(wifi.nameAvailabilityMessage?.contains("has not provided") == true)
    #expect(wifi.requestNamesButtonTitle == "Refresh network name")
  }

  @Test("disabled system Location Services is explained even when app permission is allowed")
  func disabledServices() {
    let wifi = makeWiFi(ssid: nil, enabled: false)
    #expect(!wifi.canReadNetworkNames)
    #expect(wifi.nameAvailabilityMessage?.contains("Turn on Location Services") == true)
  }

  @Test("denied permission produces an actionable explanation")
  func denied() {
    let wifi = makeWiFi(ssid: nil, authorization: .denied)
    #expect(!wifi.hasLocationPermission)
    #expect(wifi.nameAvailabilityMessage?.contains("Allow Location access") == true)
  }

  @Test("a network name becomes usable on the next refresh without relabeling unknown traffic")
  func nameAppears() {
    let state = State(ssid: nil)
    let wifi = WiFiInfo(snapshotReader: { state.snapshot }, monitorsEvents: false)
    let originalRevision = wifi.connectionRevision
    state.snapshot.ssid = "Home"
    wifi.refresh()
    #expect(wifi.canReadNetworkNames)
    #expect(wifi.networkIdentity == .named("Home"))
    #expect(wifi.nameAvailabilityMessage == nil)
    #expect(wifi.connectionRevision > originalRevision)
    wifi.refresh()
    #expect(wifi.connectionRevision == originalRevision + 1)
  }

  @Test("a missing Wi-Fi interface never defaults to an Ethernet interface")
  func noInterface() {
    let wifi = makeWiFi(ssid: nil, status: .off, interface: nil)
    #expect(wifi.interfaceName == nil)
    #expect(wifi.networkIdentity == nil)
  }

  @Test("an observed name is available even when authorization metadata is not determined")
  func observedName() {
    let wifi = makeWiFi(ssid: "Home", authorization: .notDetermined)
    #expect(wifi.canReadNetworkNames)
    #expect(wifi.nameAvailabilityMessage == nil)
  }

  private func makeWiFi(
    ssid: String?, enabled: Bool = true, authorization: CLAuthorizationStatus = .authorizedAlways,
    status: WiFiInfo.Status = .connected, interface: String? = "en0"
  ) -> WiFiInfo {
    WiFiInfo(snapshotReader: {
      WiFiInfo.Snapshot(interfaceName: interface, ssid: ssid, status: status,
                        locationAuthorization: authorization, locationServicesEnabled: enabled)
    }, monitorsEvents: false)
  }

  private final class State {
    var snapshot: WiFiInfo.Snapshot
    init(ssid: String?) {
      snapshot = WiFiInfo.Snapshot(interfaceName: "en0", ssid: ssid, status: .connected,
                                  locationAuthorization: .authorizedAlways, locationServicesEnabled: true)
    }
  }
}
