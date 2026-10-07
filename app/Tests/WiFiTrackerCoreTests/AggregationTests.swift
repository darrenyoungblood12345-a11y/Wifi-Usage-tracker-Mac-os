import Foundation
import Testing
@testable import WiFiTrackerCore

@Suite("Aggregation")
struct AggregationTests {
  let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
  }()

  func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  func record(_ date: Date, _ network: String = "Home", rx: UInt64, tx: UInt64 = 0) -> UsageRecord {
    UsageRecord(bucket: date, network: network, bytes: ByteCounters(received: rx, sent: tx))
  }

  @Test("sums minutes into hours and fills empty hours with zero")
  func hourly() {
    let interval = DateInterval(start: date(2026, 5, 1, 9), end: date(2026, 5, 1, 12))
    let points = aggregate(
      [record(date(2026, 5, 1, 9, 5), rx: 10, tx: 1), record(date(2026, 5, 1, 9, 59), rx: 20, tx: 2), record(date(2026, 5, 1, 11, 30), rx: 5)],
      over: interval, by: .hour, calendar: calendar
    )
    #expect(points.map(\.date) == [date(2026, 5, 1, 9), date(2026, 5, 1, 10), date(2026, 5, 1, 11)])
    #expect(points.map(\.bytes) == [ByteCounters(received: 30, sent: 3), .zero, ByteCounters(received: 5, sent: 0)])
  }

  @Test("uses local calendar days across a DST change (23-hour day)")
  func dstDay() {
    // US clocks spring forward on 8 March 2026, so that day is 23 hours long.
    let interval = DateInterval(start: date(2026, 3, 7), end: date(2026, 3, 10))
    let days = bucketStarts(in: interval, by: .day, calendar: calendar)
    #expect(days == [date(2026, 3, 7), date(2026, 3, 8), date(2026, 3, 9)])
    #expect(days[2].timeIntervalSince(days[1]) == 23 * 3600)

    let points = aggregate([record(date(2026, 3, 8, 23, 30), rx: 7)], over: interval, by: .day, calendar: calendar)
    #expect(points[1].bytes.received == 7)
    #expect(points[2].bytes.received == 0)
  }

  @Test("groups by month")
  func monthly() {
    let interval = DateInterval(start: date(2026, 1, 1), end: date(2026, 4, 1))
    let points = aggregate([record(date(2026, 1, 31, 23, 59), rx: 1), record(date(2026, 2, 1), rx: 2), record(date(2026, 3, 15), rx: 4)],
                           over: interval, by: .month, calendar: calendar)
    #expect(points.map(\.bytes.received) == [1, 2, 4])
  }

  @Test("ranks networks by total usage")
  func byNetwork() {
    let records = [
      record(date(2026, 5, 1), "Cafe", rx: 50, tx: 10),
      record(date(2026, 5, 1), "Home", rx: 100, tx: 0),
      record(date(2026, 5, 2), "Cafe", rx: 30),
      record(date(2026, 5, 2), "Office", rx: 5),
    ]
    #expect(usageByNetwork(records) == [
      NetworkUsage(network: "Home", bytes: ByteCounters(received: 100, sent: 0)),
      NetworkUsage(network: "Cafe", bytes: ByteCounters(received: 80, sent: 10)),
      NetworkUsage(network: "Office", bytes: ByteCounters(received: 5, sent: 0)),
    ])
    #expect(totalUsage(records) == ByteCounters(received: 185, sent: 10))
  }
}

@Suite("History ranges")
struct HistoryRangeTests {
  let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/London")!
    return calendar
  }()

  func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
  }

  @Test("each range covers whole buckets ending with the current one", arguments: [
    (HistoryRange.day, 24),
    (.week, 7),
    (.month, 30),
    (.year, 12),
  ])
  func bucketCount(range: HistoryRange, expected: Int) {
    let now = date(2026, 10, 7, 14, 37)
    let interval = range.interval(now: now, calendar: calendar)
    #expect(bucketStarts(in: interval, by: range.granularity, calendar: calendar).count == expected)
    #expect(interval.contains(now))
  }

  @Test("the 24-hour range ends at the top of the next hour")
  func dayBounds() {
    let interval = HistoryRange.day.interval(now: date(2026, 10, 7, 14, 37), calendar: calendar)
    #expect(interval.start == date(2026, 10, 6, 15))
    #expect(interval.end == date(2026, 10, 7, 15))
  }
}
