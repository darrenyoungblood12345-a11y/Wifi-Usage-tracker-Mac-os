import Testing
@testable import WiFiTrackerCore

@Suite("Formatting")
struct FormattersTests {
  @Test("formats byte totals with decimal units and three significant digits", arguments: [
    (UInt64(0), "0 B"),
    (999, "999 B"),
    (1_000, "1.00 KB"),
    (45_600, "45.6 KB"),
    (999_499, "999 KB"),
    (999_600, "1.00 MB"),
    (1_234_567_890, "1.23 GB"),
    (2_500_000_000_000, "2.50 TB"),
  ])
  func bytes(input: UInt64, expected: String) {
    #expect(formatBytes(input) == expected)
  }

  @Test("formats rates in bytes or bits per second")
  func rates() {
    #expect(formatRate(0, unit: .bytes) == "0 KB/s")
    #expect(formatRate(20, unit: .bytes) == "0 KB/s")
    #expect(formatRate(512, unit: .bytes) == "0.51 KB/s")
    #expect(formatRate(84_000, unit: .bytes) == "84.0 KB/s")
    #expect(formatRate(1_250_000, unit: .bytes) == "1.25 MB/s")
    #expect(formatRate(1_250_000, unit: .bits) == "10.0 Mbps")
    #expect(formatRate(-5, unit: .bits) == "0 Kbps")
  }
}
