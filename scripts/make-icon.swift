// Draws the 1024×1024 app icon: a Wi-Fi glyph above a small traffic graph on a blue squircle.
// Usage: swift scripts/make-icon.swift <output.png>

import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
  NSColor(
    srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
    green: CGFloat((hex >> 8) & 0xFF) / 255,
    blue: CGFloat(hex & 0xFF) / 255,
    alpha: alpha
  )
}

guard let bitmap = NSBitmapImageRep(
  bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
  fatalError("Couldn't create a drawing context")
}
NSGraphicsContext.current = context

// macOS icon grid: an 824pt body inset 100pt, with a soft drop shadow.
let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let squircle = NSBezierPath(roundedRect: body, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = color(0x000000, alpha: 0.28)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
color(0x123A8C).setFill()
squircle.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [color(0x3B8EF0), color(0x1C55C4), color(0x0E2F7A)])?
  .draw(in: squircle, angle: -90)

// Traffic graph along the bottom: a translucent download area and an orange upload line.
NSGraphicsContext.saveGraphicsState()
squircle.addClip()
let graphPoints: [CGFloat] = [0.30, 0.42, 0.36, 0.55, 0.48, 0.66, 0.52, 0.62, 0.44, 0.58, 0.50]
let graphBase: CGFloat = 100
let graphHeight: CGFloat = 230
func graphPath(_ values: [CGFloat], scale: CGFloat) -> NSBezierPath {
  let path = NSBezierPath()
  let step = body.width / CGFloat(values.count - 1)
  for (index, value) in values.enumerated() {
    let point = NSPoint(x: body.minX + CGFloat(index) * step, y: graphBase + value * graphHeight * scale)
    if index == 0 { path.move(to: point) } else {
      let previous = path.currentPoint
      let midX = (previous.x + point.x) / 2
      path.curve(to: point, controlPoint1: NSPoint(x: midX, y: previous.y), controlPoint2: NSPoint(x: midX, y: point.y))
    }
  }
  return path
}
let area = graphPath(graphPoints, scale: 1)
area.line(to: NSPoint(x: body.maxX, y: graphBase))
area.line(to: NSPoint(x: body.minX, y: graphBase))
area.close()
color(0xFFFFFF, alpha: 0.16).setFill()
area.fill()
let downloadLine = graphPath(graphPoints, scale: 1)
downloadLine.lineWidth = 14
downloadLine.lineCapStyle = .round
color(0x9CC8FF).setStroke()
downloadLine.stroke()
let uploadLine = graphPath(graphPoints.map { $0 * 0.45 + 0.05 }, scale: 1)
uploadLine.lineWidth = 14
uploadLine.lineCapStyle = .round
color(0xFF8A57).setStroke()
uploadLine.stroke()
NSGraphicsContext.restoreGraphicsState()

// Wi-Fi glyph, white, centred in the upper part of the icon.
let configuration = NSImage.SymbolConfiguration(pointSize: 440, weight: .semibold)
  .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "wifi", accessibilityDescription: nil)?
  .withSymbolConfiguration(configuration) {
  let glyph = symbol.size
  let origin = NSPoint(x: (size - glyph.width) / 2, y: 585 - glyph.height / 2)
  NSGraphicsContext.saveGraphicsState()
  let glow = NSShadow()
  glow.shadowColor = color(0x000000, alpha: 0.18)
  glow.shadowBlurRadius = 16
  glow.shadowOffset = NSSize(width: 0, height: -6)
  glow.set()
  symbol.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
  NSGraphicsContext.restoreGraphicsState()
}

context.flushGraphics()
guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("PNG encoding failed") }
try png.write(to: URL(fileURLWithPath: output))
print("Wrote \(output)")
