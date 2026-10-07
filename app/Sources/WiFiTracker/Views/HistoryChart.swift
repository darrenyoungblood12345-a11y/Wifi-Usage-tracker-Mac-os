import Charts
import SwiftUI
import WiFiTrackerCore

/// Stacked download/upload columns per hour, day or month.
struct HistoryChart: View {
  let points: [UsagePoint]
  let range: HistoryRange
  let interval: DateInterval

  @State private var hoveredDate: Date?

  private var hovered: UsagePoint? {
    guard let hoveredDate else { return nil }
    return points.last { $0.date <= hoveredDate }
  }

  private var yMax: Double {
    max(Double(points.map(\.bytes.total).max() ?? 0) * 1.1, 1_000_000)
  }

  var body: some View {
    GeometryReader { geometry in
      let slot = (geometry.size.width - 70) / CGFloat(max(points.count, 1))
      let barWidth = min(24, max(3, slot * 0.6))
      chart(barWidth: barWidth)
    }
    .overlay {
      if points.allSatisfy({ $0.bytes.total == 0 }) {
        Text("No usage recorded in this period yet")
          .font(.callout)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func chart(barWidth: CGFloat) -> some View {
    Chart {
      ForEach(points) { point in
        let received = Double(point.bytes.received)
        let total = Double(point.bytes.total)
        let isTop = point.bytes.sent == 0
        let dimmed = hovered != nil && hovered?.date != point.date

        BarMark(
          x: .value("Time", point.date, unit: range.granularity.component),
          yStart: .value("Bytes", 0),
          yEnd: .value("Bytes", received),
          width: .fixed(barWidth)
        )
        .foregroundStyle(Palette.download)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: isTop ? 4 : 0, topTrailingRadius: isTop ? 4 : 0))
        .opacity(dimmed ? 0.4 : 1)

        if point.bytes.sent > 0 {
          BarMark(
            x: .value("Time", point.date, unit: range.granularity.component),
            yStart: .value("Bytes", received),
            yEnd: .value("Bytes", total),
            width: .fixed(barWidth)
          )
          .foregroundStyle(Palette.upload)
          .clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
          // The 2px surface gap that separates stacked segments.
          .offset(y: received > 0 ? -2 : 0)
          .opacity(dimmed ? 0.4 : 1)
        }
      }
    }
    .chartXScale(domain: interval.start...interval.end)
    .chartYScale(domain: 0...yMax)
    .chartLegend(.hidden)
    .chartXAxis {
      AxisMarks(values: xAxisValues) { _ in
        AxisTick(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.gridline)
        AxisValueLabel(format: xAxisFormat, centered: range != .day)
      }
    }
    .chartYAxis {
      AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
        AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.gridline)
        AxisValueLabel {
          if let bytes = value.as(Double.self) {
            Text(formatBytes(UInt64(max(0, bytes))))
          }
        }
      }
    }
    .chartOverlay { proxy in
      GeometryReader { geometry in
        Rectangle()
          .fill(.clear)
          .contentShape(Rectangle())
          .onContinuousHover { phase in
            switch phase {
            case .active(let location):
              guard !DevOptions.isSnapshotting, let frame = proxy.plotFrame else { return }
              hoveredDate = proxy.value(atX: location.x - geometry[frame].origin.x)
            case .ended:
              hoveredDate = nil
            }
          }
        if let hovered, let frame = proxy.plotFrame, let x = proxy.position(forX: hovered.date) {
          let plot = geometry[frame]
          ChartTooltip(
            title: "\(bucketTitle(hovered.date)) · \(formatBytes(hovered.bytes.total))",
            rows: [(.download, formatBytes(hovered.bytes.received)), (.upload, formatBytes(hovered.bytes.sent))]
          )
          .fixedSize()
          .tooltipPosition(anchorX: plot.minX + x, plot: plot)
          .allowsHitTesting(false)
        }
      }
    }
  }

  private var xAxisValues: AxisMarkValues {
    switch range {
    case .day: .stride(by: .hour, count: 3)
    case .week: .stride(by: .day, count: 1)
    case .month: .stride(by: .day, count: 5)
    case .year: .stride(by: .month, count: 1)
    }
  }

  private var xAxisFormat: Date.FormatStyle {
    switch range {
    case .day: .dateTime.hour()
    case .week: .dateTime.weekday(.abbreviated)
    case .month: .dateTime.month(.abbreviated).day()
    case .year: .dateTime.month(.abbreviated)
    }
  }

  private func bucketTitle(_ date: Date) -> String {
    switch range {
    case .day: date.formatted(.dateTime.weekday(.abbreviated).hour())
    case .week, .month: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    case .year: date.formatted(.dateTime.month(.wide).year())
    }
  }
}

/// The same numbers as the chart, for anyone who'd rather read than hover.
struct HistoryTable: View {
  let points: [UsagePoint]
  let range: HistoryRange

  var body: some View {
    Table(points.reversed()) {
      TableColumn("Period") { point in
        Text(periodLabel(point.date))
      }
      TableColumn("Download") { point in
        Text(formatBytes(point.bytes.received)).monospacedDigit()
      }
      TableColumn("Upload") { point in
        Text(formatBytes(point.bytes.sent)).monospacedDigit()
      }
      TableColumn("Total") { point in
        Text(formatBytes(point.bytes.total)).monospacedDigit().fontWeight(.medium)
      }
    }
  }

  private func periodLabel(_ date: Date) -> String {
    switch range {
    case .day: date.formatted(.dateTime.weekday(.abbreviated).hour())
    case .week, .month: date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    case .year: date.formatted(.dateTime.month(.wide).year())
    }
  }
}
