import SwiftUI
import WiFiTrackerCore

/// Network name with its connection state.
struct NetworkHeading: View {
  let wifi: WiFiInfo
  var compact = false

  var body: some View {
    HStack(spacing: compact ? 8 : 12) {
      Image(systemName: wifi.status == .off ? "wifi.slash" : "wifi")
        .font(compact ? .body.weight(.semibold) : .title2.weight(.semibold))
        .foregroundStyle(wifi.status == .connected ? Color.accentColor : .secondary)
        .frame(width: compact ? 28 : 44, height: compact ? 28 : 44)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: compact ? 7 : 11))
      VStack(alignment: .leading, spacing: 1) {
        Text(wifi.status == .connected ? wifi.networkName : "No network")
          .font(compact ? .headline : .title2.weight(.semibold))
          .lineLimit(1)
        Text(wifi.statusText)
          .font(compact ? .caption : .subheadline)
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// A live speed with a colored key beside it; the number itself stays in text color.
struct RateReadout: View {
  let direction: Direction
  let value: Double
  let unit: RateUnit
  var size: CGFloat = 34

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      SeriesKey(direction: direction)
      Text(formatRate(value, unit: unit))
        .font(.system(size: size, weight: .semibold))
        .monospacedDigit()
        .contentTransition(.numericText())
    }
    .accessibilityElement(children: .combine)
  }
}

/// A short stroke of the series color plus its name.
struct SeriesKey: View {
  let direction: Direction
  var showsLabel = true

  var body: some View {
    HStack(spacing: 6) {
      Capsule()
        .fill(direction.color)
        .frame(width: 12, height: 3)
      if showsLabel {
        Text(direction.rawValue)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }
}

/// "1.2 GB ↓  140 MB ↑" with colored keys, stacked or on one line.
struct DirectionBreakdown: View {
  let bytes: ByteCounters
  var inline = false

  var body: some View {
    let layout = inline ? AnyLayout(HStackLayout(spacing: 12)) : AnyLayout(VStackLayout(alignment: .trailing, spacing: 3))
    layout {
      row(.download, bytes.received)
      row(.upload, bytes.sent)
    }
  }

  private func row(_ direction: Direction, _ value: UInt64) -> some View {
    HStack(spacing: 6) {
      Text(formatBytes(value))
        .font(.callout)
        .monospacedDigit()
      Image(systemName: direction.symbol)
        .font(.caption2.weight(.bold))
        .foregroundStyle(direction.color)
        .accessibilityLabel(direction.rawValue)
    }
  }
}

struct Card<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .padding(18)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
      .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.cardBorder))
  }
}

struct StatTile: View {
  let title: String
  let bytes: ByteCounters

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 10) {
        Text(title)
          .font(.subheadline)
          .foregroundStyle(.secondary)
        Text(formatBytes(bytes.total))
          .font(.system(size: 26, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        HStack(spacing: 12) {
          label(.download, bytes.received)
          label(.upload, bytes.sent)
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  private func label(_ direction: Direction, _ value: UInt64) -> some View {
    HStack(spacing: 4) {
      Image(systemName: direction.symbol)
        .font(.caption2.weight(.bold))
        .foregroundStyle(direction.color)
        .accessibilityLabel(direction.rawValue)
      Text(formatBytes(value))
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
    }
  }
}

struct ChartLegend: View {
  var body: some View {
    HStack(spacing: 14) {
      ForEach(Direction.allCases) { SeriesKey(direction: $0) }
    }
  }
}

/// Tooltip body: values lead, series names follow.
struct ChartTooltip: View {
  let title: String
  let rows: [(Direction, String)]

  var body: some View {
    VStack(alignment: .leading, spacing: 5) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
      ForEach(rows, id: \.0) { direction, value in
        HStack(spacing: 6) {
          Capsule().fill(direction.color).frame(width: 10, height: 3)
          Text(value).font(.callout.weight(.semibold)).monospacedDigit()
          Text(direction.rawValue).font(.caption).foregroundStyle(.secondary)
        }
      }
    }
    .padding(10)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.cardBorder))
    .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
  }
}
