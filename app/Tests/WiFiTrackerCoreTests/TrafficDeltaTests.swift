import Testing
@testable import WiFiTrackerCore

@Suite("Counter deltas")
struct TrafficDeltaTests {
  @Test("subtracts the previous reading")
  func normalDelta() {
    let previous = ByteCounters(received: 1_000, sent: 400)
    let current = ByteCounters(received: 6_000, sent: 900)
    #expect(current.delta(since: previous) == ByteCounters(received: 5_000, sent: 500))
  }

  @Test("treats a counter that went backwards as reset, counting the whole new value")
  func counterReset() {
    let previous = ByteCounters(received: 9_000_000, sent: 50)
    let current = ByteCounters(received: 1_200, sent: 80)
    #expect(current.delta(since: previous) == ByteCounters(received: 1_200, sent: 30))
  }

  @Test("handles counters beyond 32 bits")
  func largeCounters() {
    let previous = ByteCounters(received: 5_000_000_000, sent: 4_294_967_000)
    let current = ByteCounters(received: 5_000_100_000, sent: 4_294_968_000)
    #expect(current.delta(since: previous) == ByteCounters(received: 100_000, sent: 1_000))
  }
}

@Suite("Interface counters")
struct InterfaceCountersTests {
  @Test("reads the loopback interface from the kernel")
  func readsLoopback() throws {
    let loopback = try #require(InterfaceCounters.read(interface: "lo0"))
    #expect(loopback.total > 0)
    #expect(SystemBoot.time() != nil)
  }

  @Test("returns nil for an interface that doesn't exist")
  func missingInterface() {
    #expect(InterfaceCounters.read(interface: "nope99") == nil)
  }
}
