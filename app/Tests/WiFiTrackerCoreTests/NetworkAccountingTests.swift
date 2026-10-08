import Foundation
import Testing
@testable import WiFiTrackerCore

@Suite("Per-network accounting")
struct NetworkAccountingTests {
  private let bootTime = Date(timeIntervalSince1970: 1_700_000_000)

  private func sample(
    _ second: TimeInterval,
    received: UInt64,
    sent: UInt64 = 0,
    network: NetworkIdentity? = .named("A"),
    interface: String = "en0",
    continuity: Int = 0,
    dateOffset: TimeInterval = 0
  ) -> NetworkSample {
    NetworkSample(
      date: bootTime.addingTimeInterval(second + dateOffset),
      uptime: second,
      interface: interface,
      counters: ByteCounters(received: received, sent: sent),
      network: network,
      continuity: continuity
    )
  }

  @Test("starts with a baseline and checkpoints the latest counter reading")
  func initialBaselineAndCheckpoint() {
    var accounting = NetworkAccounting()
    #expect(accounting.checkpoint(bootTime: bootTime) == nil)
    let first = sample(10, received: 100, sent: 20)
    #expect(accounting.update(first) == nil)
    #expect(accounting.checkpoint(bootTime: bootTime) == CounterCheckpoint(
      bootTime: bootTime,
      interface: "en0",
      counters: first.counters,
      date: first.date
    ))

    let second = sample(11, received: 150, sent: 30)
    #expect(accounting.update(second) == NetworkDelta(
      bytes: ByteCounters(received: 50, sent: 10),
      network: .named("A"),
      elapsed: 1
    ))
    #expect(accounting.checkpoint(bootTime: bootTime)?.counters == second.counters)
    #expect(accounting.checkpoint(bootTime: bootTime)?.date == second.date)
  }

  @Test("repeated readings never count the same bytes twice")
  func repeatedReading() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100, sent: 20))
    let latest = sample(11, received: 150, sent: 30)
    #expect(accounting.update(latest)?.bytes == ByteCounters(received: 50, sent: 10))
    #expect(accounting.update(latest) == nil)
    #expect(accounting.update(sample(12, received: 170, sent: 35))?.bytes
      == ByteCounters(received: 20, sent: 5))
  }

  @Test("a network switch preserves bytes without charging either endpoint")
  func networkSwitch() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100, sent: 20))
    #expect(accounting.update(sample(11, received: 150, sent: 30, network: .named("B")))
      == NetworkDelta(bytes: ByteCounters(received: 50, sent: 10), network: .unattributed, elapsed: 1))
    #expect(accounting.update(sample(12, received: 190, sent: 35, network: .named("B")))
      == NetworkDelta(bytes: ByteCounters(received: 40, sent: 5), network: .named("B"), elapsed: 1))
  }

  @Test("disconnect and same-name reconnect keep both boundary intervals unattributed")
  func sameNameReconnect() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100))
    #expect(accounting.update(sample(11, received: 120, network: nil))
      == NetworkDelta(bytes: ByteCounters(received: 20, sent: 0), network: .unattributed, elapsed: 1))
    #expect(accounting.update(sample(12, received: 170))
      == NetworkDelta(bytes: ByteCounters(received: 50, sent: 0), network: .unattributed, elapsed: 1))
    #expect(accounting.update(sample(13, received: 180))?.network == .named("A"))
  }

  @Test("disconnect followed by a different network preserves all comparable traffic")
  func differentNetworkReconnect() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100))
    let disconnected = accounting.update(sample(11, received: 120, network: nil))
    let reconnected = accounting.update(sample(12, received: 150, network: .named("B")))
    #expect(disconnected?.network == .unattributed)
    #expect(reconnected?.network == .unattributed)
    #expect((disconnected?.bytes ?? .zero) + (reconnected?.bytes ?? .zero)
      == ByteCounters(received: 50, sent: 0))
  }

  @Test("unavailable names and their recovery never relabel earlier bytes")
  func nameLossAndRecovery() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100))
    let lost = accounting.update(sample(11, received: 120, network: .unattributed))
    let unavailable = accounting.update(sample(12, received: 150, network: .unattributed))
    let recovered = accounting.update(sample(13, received: 180))
    #expect(lost?.network == .unattributed)
    #expect(unavailable?.network == .unattributed)
    #expect(recovered?.network == .unattributed)
    #expect((lost?.bytes ?? .zero) + (unavailable?.bytes ?? .zero) + (recovered?.bytes ?? .zero)
      == ByteCounters(received: 80, sent: 0))
    #expect(accounting.update(sample(14, received: 200))?.network == .named("A"))
  }

  @Test("continuous traffic with no readable name still has a valid live speed")
  func unnamedTrafficIsLive() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100, sent: 20, network: .unattributed))
    #expect(accounting.update(sample(11, received: 150, sent: 25, network: .unattributed))
      == NetworkDelta(bytes: ByteCounters(received: 50, sent: 5), network: .unattributed, elapsed: 1, isLive: true))
  }

  @Test("a missed read retains bytes while preventing a stale recovered live speed")
  func missedRead() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100, sent: 20))
    accounting.invalidateContinuity()
    accounting.invalidateContinuity()
    #expect(accounting.update(sample(12, received: 180, sent: 35))
      == NetworkDelta(bytes: ByteCounters(received: 80, sent: 15), network: .unattributed, elapsed: 2, isLive: false))
    #expect(accounting.update(sample(13, received: 200, sent: 40))
      == NetworkDelta(bytes: ByteCounters(received: 20, sent: 5), network: .named("A"), elapsed: 1, isLive: true))
  }

  @Test("an observed reconnect event invalidates matching network names")
  func continuityGeneration() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100, continuity: 7))
    #expect(accounting.update(sample(11, received: 160, continuity: 8))
      == NetworkDelta(bytes: ByteCounters(received: 60, sent: 0), network: .unattributed, elapsed: 1))
    #expect(accounting.update(sample(12, received: 180, continuity: 8))?.network == .named("A"))
  }

  @Test("a wake or suspended interval preserves totals without reporting them as live speed")
  func longGap() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100, sent: 20))
    #expect(accounting.update(sample(910, received: 1_000, sent: 120))
      == NetworkDelta(bytes: ByteCounters(received: 900, sent: 100), network: .unattributed, elapsed: 900, isLive: false))
    #expect(accounting.update(sample(911, received: 1_100, sent: 125))?.network == .named("A"))
  }

  @Test("clock adjustments invalidate attribution while elapsed time stays monotonic")
  func monotonicTime() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100))
    #expect(accounting.update(sample(13, received: 130, dateOffset: -3_600))
      == NetworkDelta(bytes: ByteCounters(received: 30, sent: 0), network: .unattributed, elapsed: 3, isLive: false))
    #expect(accounting.update(sample(16, received: 150, dateOffset: 3_600))
      == NetworkDelta(bytes: ByteCounters(received: 20, sent: 0), network: .unattributed, elapsed: 3, isLive: false))
  }

  @Test("a long wall-clock sleep gap is unattributed even when uptime barely advances")
  func sleepExcludedFromUptime() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100, sent: 20))
    #expect(accounting.update(sample(11, received: 180, sent: 35, dateOffset: 900))
      == NetworkDelta(bytes: ByteCounters(received: 80, sent: 15), network: .unattributed, elapsed: 1, isLive: false))
    #expect(accounting.update(sample(12, received: 200, sent: 40, dateOffset: 900))?.network == .named("A"))
  }

  @Test("new bytes without a positive monotonic interval are preserved without live speed")
  func zeroMonotonicInterval() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100))
    #expect(accounting.update(sample(10, received: 150, dateOffset: 1))
      == NetworkDelta(bytes: ByteCounters(received: 50, sent: 0), network: .unattributed, elapsed: 0, isLive: false))
  }

  @Test("new bytes without a positive wall-clock interval are preserved without live speed")
  func zeroWallClockInterval() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100))
    #expect(accounting.update(sample(11, received: 150, dateOffset: -1))
      == NetworkDelta(bytes: ByteCounters(received: 50, sent: 0), network: .unattributed, elapsed: 1, isLive: false))
  }

  @Test("replacing the interface starts a new counter baseline")
  func replacementInterface() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 1_000, sent: 200))
    #expect(accounting.update(sample(11, received: 100, sent: 20, interface: "en1")) == nil)
    #expect(accounting.checkpoint(bootTime: bootTime)?.interface == "en1")
    #expect(accounting.update(sample(12, received: 140, sent: 25, interface: "en1"))
      == NetworkDelta(bytes: ByteCounters(received: 40, sent: 5), network: .named("A"), elapsed: 1))
  }

  @Test("reset counters preserve new traffic while invalidating known attribution")
  func counterReset() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 1_000, sent: 200))
    #expect(accounting.update(sample(11, received: 40, sent: 220))
      == NetworkDelta(bytes: ByteCounters(received: 40, sent: 20), network: .unattributed, elapsed: 1, isLive: false))
    #expect(accounting.update(sample(12, received: 60, sent: 230))?.network == .named("A"))
  }

  @Test("an out-of-order sample cannot move the boundary backwards and recount bytes")
  func backwardsUptime() {
    var accounting = NetworkAccounting()
    _ = accounting.update(sample(10, received: 100))
    #expect(accounting.update(sample(9, received: 80)) == nil)
    #expect(accounting.checkpoint(bootTime: bootTime)?.counters == ByteCounters(received: 100, sent: 0))
    #expect(accounting.update(sample(11, received: 120))
      == NetworkDelta(bytes: ByteCounters(received: 20, sent: 0), network: .unattributed, elapsed: 1, isLive: false))
  }

  @Test("a real SSID named Wi-Fi has a distinct identity from unattributed traffic")
  func realGenericName() {
    let named = NetworkIdentity.named("Wi-Fi")
    #expect(named != .unattributed)
    #expect(named.storageName == "Wi-Fi")
    #expect(named.displayName == "Wi-Fi")
    #expect(!named.isUnattributed)
    #expect(NetworkIdentity.unattributed.storageName == "")
    #expect(NetworkIdentity.unattributed.displayName == "Unattributed Wi-Fi")
    #expect(NetworkIdentity.unattributed.isUnattributed)
  }

  @Test("restart recovery is unattributed even if the same SSID is visible")
  func restartRecovery() throws {
    var accounting = NetworkAccounting()
    let saved = CounterCheckpoint(
      bootTime: bootTime,
      interface: "en0",
      counters: ByteCounters(received: 100, sent: 20),
      date: bootTime.addingTimeInterval(10)
    )
    let current = sample(70, received: 1_000, sent: 120)
    #expect(accounting.restore(saved, bootTime: bootTime, sample: current)
      == NetworkDelta(bytes: ByteCounters(received: 900, sent: 100), network: .unattributed, elapsed: 60, isLive: false))
    #expect(accounting.update(current) == nil)
    #expect(accounting.update(sample(71, received: 1_100, sent: 125))?.network == .named("A"))

    let restoredCheckpoint = try #require(accounting.checkpoint(bootTime: bootTime))
    let encoded = try JSONEncoder().encode(restoredCheckpoint)
    #expect(try JSONDecoder().decode(CounterCheckpoint.self, from: encoded) == restoredCheckpoint)
  }

  @Test("restart with unchanged counters recovers zero additional traffic")
  func unchangedRestartCounters() {
    var accounting = NetworkAccounting()
    let current = sample(10, received: 100, sent: 20)
    let saved = CounterCheckpoint(
      bootTime: bootTime,
      interface: current.interface,
      counters: current.counters,
      date: current.date
    )
    #expect(accounting.restore(saved, bootTime: bootTime, sample: current) == nil)
    #expect(accounting.checkpoint(bootTime: bootTime) == saved)
    #expect(accounting.update(sample(11, received: 120, sent: 25))?.bytes
      == ByteCounters(received: 20, sent: 5))
  }

  @Test("a checkpoint from a different boot is rejected without counting its counters")
  func differentBoot() {
    var accounting = NetworkAccounting()
    let saved = CounterCheckpoint(
      bootTime: bootTime.addingTimeInterval(-10_000),
      interface: "en0",
      counters: ByteCounters(received: 1_000, sent: 200),
      date: bootTime.addingTimeInterval(-100)
    )
    #expect(accounting.restore(saved, bootTime: bootTime, sample: sample(10, received: 100, sent: 20)) == nil)
    #expect(accounting.update(sample(11, received: 120, sent: 25))?.bytes
      == ByteCounters(received: 20, sent: 5))
  }

  @Test("restart recovery never compares checkpoints from different interfaces")
  func differentRestartInterface() {
    var accounting = NetworkAccounting()
    let saved = CounterCheckpoint(
      bootTime: bootTime,
      interface: "en1",
      counters: ByteCounters(received: 1_000, sent: 200),
      date: bootTime.addingTimeInterval(10)
    )
    #expect(accounting.restore(saved, bootTime: bootTime, sample: sample(20, received: 100, sent: 20)) == nil)
    #expect(accounting.update(sample(21, received: 120, sent: 25))?.bytes
      == ByteCounters(received: 20, sent: 5))
  }

  @Test("small boot timestamp rounding is allowed but a changed boot is rejected")
  func bootTimeTolerance() {
    let current = sample(20, received: 150)
    let saved = CounterCheckpoint(
      bootTime: bootTime,
      interface: "en0",
      counters: ByteCounters(received: 100, sent: 0),
      date: bootTime.addingTimeInterval(10)
    )
    var accepted = NetworkAccounting()
    #expect(accepted.restore(saved, bootTime: bootTime.addingTimeInterval(5), sample: current)?.bytes
      == ByteCounters(received: 50, sent: 0))
    var rejected = NetworkAccounting()
    #expect(rejected.restore(saved, bootTime: bootTime.addingTimeInterval(5.01), sample: current) == nil)
  }
}
