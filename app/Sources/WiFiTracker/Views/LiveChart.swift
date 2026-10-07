import Charts
import SwiftUI
import WiFiTrackerCore

/// Download and upload speed over the last few minutes, with a hover crosshair.
struct LiveChart: View {
  let samples: [RateSample]
  let unit: RateUnit
  var window: TimeInterval = 60
  var compact = false

  @State private var hoveredDate: Date?

  private var points: [RateSample] { downsample(samples, limit: 300) }

  private var hovered: RateSample? {
    guard let hoveredDate, !points.isEmpty else { return nil }
    return points.min { abs($0.date.timeIntervalSince(hoveredDate)) < abs($1.date.timeIntervalSince(hoveredDate)) }
  }

  /// Keeps an idle connection from filling the chart with noise.
  private var yMax: Double {
    max((points.map { max($0.download, $0.upload) }.max() ?? 0) * 1.15, 10_000)
  }

  private var xDomain: ClosedRange<Date> {
    let end = samples.last?.date ?? .now
    return end.addingTimeInterval(-window)...end
  }

  /// Evenly spaced ticks across the window, so labels stay put while the data scrolls past.
  private var xTicks: [Date] {
    let divisions = window <= 60 ? 4 : 5
    return (0...divisions).map { xDomain.lowerBound.addingTimeInterval(window * Double($0) / Double(divisions)) }
  }

  private func relativeLabel(for date: Date) -> String {
    let secondsAgo = Int(xDomain.upperBound.timeIntervalSince(date).rounded())
    guard secondsAgo > 0 else { return "now" }
    return window <= 60 ? "−\(secondsAgo)s" : "−\(secondsAgo / 60)m"
  }

  /// Edge labels hug the inside of the plot instead of being clipped.
  private func labelAnchor(for date: Date) -> UnitPoint {
    if date <= xDomain.lowerBound { return .topLeading }
    if date >= xDomain.upperBound { return .topTrailing }
    return .top
  }

  var body: some View {
    Chart {
      ForEach(points) { sample in
        ForEach(Direction.allCases) { direction in
          let value = direction == .download ? sample.download : sample.upload
          AreaMark(
            x: .value("Time", sample.date),
            y: .value("Speed", value),
            series: .value("Direction", direction.rawValue),
            stacking: .unstacked
          )
          .foregroundStyle(direction.color.opacity(0.1))
          .interpolationMethod(.monotone)

          LineMark(
            x: .value("Time", sample.date),
            y: .value("Speed", value),
            series: .value("Direction", direction.rawValue)
          )
          .foregroundStyle(direction.color)
          .lineStyle(StrokeStyle(lineWidth: compact ? 1.5 : 2, lineCap: .round, lineJoin: .round))
          .interpolationMethod(.monotone)
        }
      }

      if let hovered {
        RuleMark(x: .value("Time", hovered.date))
          .foregroundStyle(Color.secondary.opacity(0.6))
          .lineStyle(StrokeStyle(lineWidth: 1))
        ForEach(Direction.allCases) { direction in
          let value = direction == .download ? hovered.download : hovered.upload
          PointMark(x: .value("Time", hovered.date), y: .value("Speed", value))
            .symbolSize(150)
            .foregroundStyle(Color(nsColor: .controlBackgroundColor))
          PointMark(x: .value("Time", hovered.date), y: .value("Speed", value))
            .symbolSize(64)
            .foregroundStyle(direction.color)
        }
      }
    }
    .chartXScale(domain: xDomain)
    .chartYScale(domain: 0...yMax)
    .chartLegend(.hidden)
    .chartXAxis {
      if !compact {
        AxisMarks(values: xTicks) { value in
          AxisTick(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.gridline)
          if let date = value.as(Date.self) {
            AxisValueLabel(anchor: labelAnchor(for: date)) {
              Text(relativeLabel(for: date))
            }
          }
        }
      }
    }
    .chartYAxis {
      if !compact {
        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
          AxisGridLine(stroke: StrokeStyle(lineWidth: 1)).foregroundStyle(Palette.gridline)
          AxisValueLabel {
            if let speed = value.as(Double.self) {
              Text(formatRate(speed, unit: unit))
            }
          }
        }
      }
    }
    .chartOverlay { proxy in
      if !compact {
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
              title: hovered.date.formatted(date: .omitted, time: .standard),
              rows: [(.download, formatRate(hovered.download, unit: unit)), (.upload, formatRate(hovered.upload, unit: unit))]
            )
            .fixedSize()
            .tooltipPosition(anchorX: plot.minX + x, plot: plot)
            .allowsHitTesting(false)
          }
        }
      }
    }
    .accessibilityLabel("Live download and upload speed")
  }
}

extension View {
  /// Places a tooltip beside the crosshair, flipping to the left near the right edge.
  func tooltipPosition(anchorX: CGFloat, plot: CGRect) -> some View {
    alignmentGuide(.leading) { dimensions in
      let gap: CGFloat = 12
      let fitsRight = anchorX + gap + dimensions.width <= plot.maxX
      return -(fitsRight ? anchorX + gap : anchorX - gap - dimensions.width)
    }
    .alignmentGuide(.top) { _ in -(plot.minY + 4) }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
