import Foundation
import Testing
@testable import WiFiTrackerCore

@Suite("nettop parsing")
struct NettopParsingTests {
  // Trimmed from a real `nettop -L 1 -n -x -J bytes_in,bytes_out -t wifi` snapshot.
  let snapshot = """
    ,bytes_in,bytes_out,
    apsd.601,152376,85228,
    tcp4 10.75.142.86:61704<->17.57.144.27:443,152376,85228,
    Google Chrome H.43154,14558436,6611270,
    tcp4 10.75.142.86:49565<->52.26.44.205:443,4653,2194,
    quic4 10.75.142.86:53993<->17.248.245.233:443,5413,5321,
    com.apple.WebKit.Networking.812,900,100,
    tcp6 fe80::1.52000<->2606:4700::6810:84e5.443,900,100,

    """

  @Test("assigns each socket to the process line above it")
  func socketsBelongToProcesses() {
    let samples = parseNettop(snapshot)
    #expect(samples.map { "\($0.pid) \($0.process) \($0.bytes.received) \($0.bytes.sent)" } == [
      "601 apsd 152376 85228",
      "43154 Google Chrome H 4653 2194",
      "43154 Google Chrome H 5413 5321",
      "812 com.apple.WebKit.Networking 900 100",
    ])
    #expect(samples[1].socket == "tcp4 10.75.142.86:49565<->52.26.44.205:443")
  }

  @Test("adds up sockets with the same endpoints in one process")
  func duplicateSockets() {
    let samples = parseNettop("""
      mDNSResponder.684,30,3,
      udp4 *:*<->*:*,10,1,
      udp4 *:*<->*:*,20,2,
      """)
    #expect(samples == [SocketSample(pid: 684, process: "mDNSResponder", socket: "udp4 *:*<->*:*", bytes: ByteCounters(received: 30, sent: 3))])
  }

  @Test("skips headers, junk, and sockets without a readable process line")
  func ignoresJunk() {
    let samples = parseNettop("""
      tcp4 1.1.1.1:1<->2.2.2.2:2,5,5,
      ,bytes_in,bytes_out,
      no pid here,1,1,
      tcp4 1.1.1.1:3<->2.2.2.2:4,7,7,
      curl.900,abc,1,
      curl.900,8,9,
      tcp4 1.1.1.1:5<->2.2.2.2:6,8,9,
      """)
    #expect(samples.map(\.pid) == [900])
  }
}

@Suite("Socket deltas")
struct SocketDeltaTrackerTests {
  let start = Date(timeIntervalSince1970: 1_000)

  func socket(_ pid: Int32, _ port: Int, rx: UInt64, tx: UInt64 = 0, process: String = "app") -> SocketSample {
    SocketSample(pid: pid, process: process, socket: "tcp4 10.0.0.2:\(port)<->1.1.1.1:443", bytes: ByteCounters(received: rx, sent: tx))
  }

  @Test("the first snapshot only sets the baseline")
  func baseline() {
    var tracker = SocketDeltaTracker()
    #expect(tracker.update([socket(1, 5000, rx: 300_000_000)], at: start).isEmpty)
  }

  @Test("counts growth of known sockets and all of a new one, summed per process")
  func growthAndNewSockets() {
    var tracker = SocketDeltaTracker()
    _ = tracker.update([socket(1, 5000, rx: 1_000, tx: 100), socket(2, 6000, rx: 50)], at: start)
    let traffic = tracker.update([
      socket(1, 5000, rx: 1_500, tx: 120),
      socket(1, 5001, rx: 700, tx: 30),
      socket(2, 6000, rx: 50),
    ], at: start + 2)
    #expect(traffic == [ProcessTraffic(pid: 1, process: "app", bytes: ByteCounters(received: 1_200, sent: 50))])
  }

  @Test("forgets closed sockets, but not one that drops out briefly")
  func closedSockets() {
    var tracker = SocketDeltaTracker(memory: 10)
    _ = tracker.update([socket(1, 5000, rx: 1_000)], at: start)
    #expect(tracker.update([], at: start + 2).isEmpty)
    // Back within the memory window: only its growth counts.
    #expect(tracker.update([socket(1, 5000, rx: 1_100)], at: start + 4).map(\.bytes.received) == [100])
    _ = tracker.update([], at: start + 6)
    // Gone longer than the memory window, so the same endpoints count as a new socket.
    #expect(tracker.update([socket(1, 5000, rx: 40)], at: start + 20).map(\.bytes.received) == [40])
  }

  @Test("a count that goes backwards resets the baseline instead of counting")
  func countWentBackwards() {
    var tracker = SocketDeltaTracker()
    _ = tracker.update([socket(1, 5000, rx: 9_000, tx: 10)], at: start)
    #expect(tracker.update([socket(1, 5000, rx: 200, tx: 20)], at: start + 2).isEmpty)
    #expect(tracker.update([socket(1, 5000, rx: 250, tx: 20)], at: start + 4).map(\.bytes.received) == [50])
  }
}

@Suite("App bundles")
struct AppBundleTests {
  @Test("finds the outermost app bundle so helpers count as their app", arguments: [
    ("/Applications/Google Chrome.app/Contents/Frameworks/Google Chrome Framework.framework/Versions/1/Helpers/Google Chrome Helper.app/Contents/MacOS/Google Chrome Helper", "/Applications/Google Chrome.app"),
    ("/Applications/Safari.app/Contents/MacOS/Safari", "/Applications/Safari.app"),
    ("/usr/sbin/mDNSResponder", nil),
  ] as [(String, String?)])
  func outermostBundle(path: String, expected: String?) {
    #expect(outermostAppBundle(containing: path) == expected)
  }

  @Test("recognizes XPC services")
  func xpcServices() {
    #expect(isXPCService("/System/Library/Frameworks/WebKit.framework/Versions/A/XPCServices/com.apple.WebKit.Networking.xpc/Contents/MacOS/com.apple.WebKit.Networking"))
    #expect(!isXPCService("/usr/bin/curl"))
  }
}

@Suite("App usage list")
struct AppUsageListTests {
  func usage(_ id: String, rx: UInt64, tx: UInt64 = 0, name: String? = nil) -> AppUsage {
    AppUsage(id: id, name: name ?? id, bytes: ByteCounters(received: rx, sent: tx))
  }

  @Test("merges saved and unsaved usage, largest first, with the newest name")
  func mergesAndSorts() {
    let list = appUsageList(
      stored: [usage("com.apple.Safari", rx: 500), usage("curl", rx: 300)],
      pending: [usage("curl", rx: 400, name: "curl (new)"), usage("com.apple.Music", rx: 100)],
      wifiTotal: ByteCounters(received: 800, sent: 0)
    )
    #expect(list.map(\.name) == ["curl (new)", "com.apple.Safari", "com.apple.Music"])
    #expect(list.map(\.bytes.received) == [700, 500, 100])
  }

  @Test("adds Wi-Fi traffic the saved app usage doesn't cover as a last Other row")
  func otherTraffic() {
    let list = appUsageList(
      stored: [usage("a", rx: 100, tx: 50)],
      pending: [usage("b", rx: 1_000)],
      wifiTotal: ByteCounters(received: 160, sent: 40)
    )
    #expect(list.map(\.id) == ["b", "a", AppUsage.otherID])
    #expect(list.last?.bytes == ByteCounters(received: 60, sent: 0))
  }

  @Test("leaves Other out when apps account for everything")
  func noOther() {
    let list = appUsageList(stored: [usage("a", rx: 100)], pending: [], wifiTotal: ByteCounters(received: 90, sent: 0))
    #expect(list.map(\.id) == ["a"])
    #expect(unattributed(wifi: ByteCounters(received: 5, sent: 9), apps: ByteCounters(received: 7, sent: 4)) == ByteCounters(received: 0, sent: 5))
  }

  @Test("buckets dates by hour")
  func hours() {
    #expect(hourBucket(for: Date(timeIntervalSince1970: 7_259)) == Date(timeIntervalSince1970: 7_200))
  }
}
