import Foundation

/// One socket's cumulative byte counts from a `nettop` snapshot.
public struct SocketSample: Equatable, Sendable {
  public var pid: Int32
  /// The owning process's name as `nettop` prints it (cut to 15 characters).
  public var process: String
  /// Protocol and endpoints, e.g. `tcp4 10.0.0.5:49565<->52.26.44.205:443`.
  public var socket: String
  public var bytes: ByteCounters

  public init(pid: Int32, process: String, socket: String, bytes: ByteCounters) {
    self.pid = pid
    self.process = process
    self.socket = socket
    self.bytes = bytes
  }
}

/// Parses `nettop -L 1 -x -J bytes_in,bytes_out` output: a header, then each process line
/// (`name.pid,in,out,`) followed by its socket lines (`tcp4 a:1<->b:2,in,out,`).
///
/// Process lines are only used to know which process the following sockets belong to: their
/// figures add up the sockets open right now, so they drop whenever a connection closes.
/// Sockets with the same endpoints in the same process are added together.
public func parseNettop(_ output: String) -> [SocketSample] {
  struct State {
    var process: (pid: Int32, name: String)?
    var samples: [SocketSample] = []
    var positions: [String: Int] = [:]
  }
  return output.split(whereSeparator: \.isNewline).reduce(into: State()) { state, line in
    guard let row = nettopRow(line) else { return }
    guard row.label.contains("<->") else {
      state.process = processLabel(row.label)
      return
    }
    guard let process = state.process else { return }
    let key = "\(process.pid) \(row.label)"
    if let position = state.positions[key] {
      state.samples[position].bytes += row.bytes
    } else {
      state.positions[key] = state.samples.count
      state.samples.append(SocketSample(pid: process.pid, process: process.name, socket: row.label, bytes: row.bytes))
    }
  }.samples
}

/// `label,bytes_in,bytes_out,` → the label and its counts. Read from the right, since only the label could contain commas.
private func nettopRow(_ line: Substring) -> (label: String, bytes: ByteCounters)? {
  let fields = line.split(separator: ",", omittingEmptySubsequences: false)
  let values = fields.last?.isEmpty == true ? fields.dropLast() : fields[...]
  guard values.count >= 3,
        let sent = UInt64(values[values.endIndex - 1]),
        let received = UInt64(values[values.endIndex - 2])
  else { return nil }
  let label = values.dropLast(2).joined(separator: ",")
  return (label, ByteCounters(received: received, sent: sent))
}

/// `com.apple.WebKit.Networking.123` → (123, `com.apple.WebKit.Networking`): the pid follows the last dot.
private func processLabel(_ label: String) -> (pid: Int32, name: String)? {
  guard let dot = label.lastIndex(of: "."), let pid = Int32(label[label.index(after: dot)...]) else { return nil }
  return (pid, String(label[..<dot]))
}

/// Bytes one process moved between two snapshots.
public struct ProcessTraffic: Equatable, Sendable {
  public var pid: Int32
  public var process: String
  public var bytes: ByteCounters

  public init(pid: Int32, process: String, bytes: ByteCounters) {
    self.pid = pid
    self.process = process
    self.bytes = bytes
  }
}

/// Turns successive snapshots of per-socket totals into bytes moved per process.
///
/// A socket seen before contributes its growth, and a new one everything it has moved, since it
/// opened after the previous snapshot. Whatever a socket moved after the last snapshot before it
/// closed is missed; callers report that as Wi-Fi traffic no app accounts for.
public struct SocketDeltaTracker: Sendable {
  private struct Key: Hashable, Sendable {
    let pid: Int32
    let socket: String
  }

  private struct Seen: Sendable {
    var bytes: ByteCounters
    var date: Date
  }

  private var sockets: [Key: Seen] = [:]
  private var hasBaseline = false
  /// How long a socket missing from snapshots is remembered, so one that drops out briefly isn't counted again in full.
  private let memory: TimeInterval

  public init(memory: TimeInterval = 60) {
    self.memory = memory
  }

  /// Bytes moved per process since the previous snapshot. The first snapshot only sets the baseline.
  public mutating func update(_ samples: [SocketSample], at date: Date) -> [ProcessTraffic] {
    sockets = sockets.filter { date.timeIntervalSince($0.value.date) <= memory }
    let traffic = hasBaseline ? samples.map { ($0, growth(of: $0)) } : []
    hasBaseline = true
    samples.forEach { sockets[Key(pid: $0.pid, socket: $0.socket)] = Seen(bytes: $0.bytes, date: date) }

    return traffic
      .filter { $0.1.total > 0 }
      .reduce(into: [Int32: ProcessTraffic]()) { processes, item in
        let (sample, bytes) = item
        processes[sample.pid, default: ProcessTraffic(pid: sample.pid, process: sample.process, bytes: .zero)].bytes += bytes
      }
      .values
      .sorted { $0.pid < $1.pid }
  }

  /// A count that went backwards means the endpoints now belong to a different socket (or one of
  /// several merged sockets closed), so it only resets the baseline rather than guessing.
  private func growth(of sample: SocketSample) -> ByteCounters {
    guard let previous = sockets[Key(pid: sample.pid, socket: sample.socket)]?.bytes else { return sample.bytes }
    guard sample.bytes.received >= previous.received, sample.bytes.sent >= previous.sent else { return .zero }
    return sample.bytes.delta(since: previous)
  }
}

/// The outermost `.app` bundle containing `path`, so helpers such as
/// `Google Chrome.app/…/Google Chrome Helper.app/…` count as their app.
public func outermostAppBundle(containing path: String) -> String? {
  let components = path.split(separator: "/", omittingEmptySubsequences: false)
  guard let index = components.firstIndex(where: { $0.hasSuffix(".app") }) else { return nil }
  return components[...index].joined(separator: "/")
}

/// Whether `path` is inside an XPC service bundle (e.g. Safari's `com.apple.WebKit.Networking.xpc`),
/// whose traffic belongs to the app that launched it.
public func isXPCService(_ path: String) -> Bool {
  path.contains(".xpc/")
}
