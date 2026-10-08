import Darwin
import Foundation

/// Cumulative byte counts for one network interface (or a delta between two readings).
public struct ByteCounters: Equatable, Hashable, Sendable {
  public var received: UInt64
  public var sent: UInt64

  public init(received: UInt64, sent: UInt64) {
    self.received = received
    self.sent = sent
  }

  public static let zero = ByteCounters(received: 0, sent: 0)

  public var total: UInt64 { received + sent }

  public static func + (lhs: ByteCounters, rhs: ByteCounters) -> ByteCounters {
    ByteCounters(received: lhs.received + rhs.received, sent: lhs.sent + rhs.sent)
  }

  public static func += (lhs: inout ByteCounters, rhs: ByteCounters) {
    lhs = lhs + rhs
  }

  /// Bytes transferred since `previous`. Kernel counters only go backwards when an
  /// interface is reset, in which case everything in the new reading is new traffic.
  public func delta(since previous: ByteCounters) -> ByteCounters {
    ByteCounters(
      received: counterDelta(from: previous.received, to: received),
      sent: counterDelta(from: previous.sent, to: sent)
    )
  }
}

func counterDelta(from previous: UInt64, to current: UInt64) -> UInt64 {
  current >= previous ? current - previous : current
}

public enum InterfaceCounters {
  /// Reads the kernel's 64-bit byte counters for one interface (`en0`, `lo0`, …), or `nil` if it doesn't exist.
  ///
  /// Uses the interface MIB (`net.link.generic.ifdata.<index>.general`), the same source as `netstat -ib`.
  /// `getifaddrs` and the routing-socket list (`NET_RT_IFLIST2`) hand back counters truncated to 32 bits,
  /// which wrap every 4 GB.
  public static func read(interface name: String) -> ByteCounters? {
    let index = if_nametoindex(name)
    guard index != 0 else { return nil }
    var mib: [Int32] = [CTL_NET, PF_LINK, NETLINK_GENERIC, IFMIB_IFDATA, Int32(index), IFDATA_GENERAL]
    var data = ifmibdata()
    var size = MemoryLayout<ifmibdata>.size
    guard sysctl(&mib, UInt32(mib.count), &data, &size, nil, 0) == 0 else { return nil }
    return ByteCounters(received: data.ifmd_data.ifi_ibytes, sent: data.ifmd_data.ifi_obytes)
  }
}

public enum SystemBoot {
  /// When the kernel booted. Interface counters reset on reboot, so this tells us whether
  /// a saved counter reading is still comparable to a fresh one.
  public static func time() -> Date? {
    var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
    var value = timeval()
    var size = MemoryLayout<timeval>.size
    guard sysctl(&mib, UInt32(mib.count), &value, &size, nil, 0) == 0 else { return nil }
    return Date(timeIntervalSince1970: TimeInterval(value.tv_sec) + TimeInterval(value.tv_usec) / 1_000_000)
  }
}
