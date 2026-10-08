import AppKit

let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let context = NSGraphicsContext(bitmapImageRep: bitmap)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        let p = CGFloat(pixels)
        // Draw at every native icon size, keeping the small Spotlight image crisp.
        let tile = NSBezierPath(roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88),
                                xRadius: p * 0.20, yRadius: p * 0.20)
        let navy = NSColor(calibratedRed: 0.06, green: 0.23, blue: 0.35, alpha: 1)
        let teal = NSColor(calibratedRed: 0.08, green: 0.65, blue: 0.69, alpha: 1)
        NSGradient(starting: navy, ending: teal)!.draw(in: tile, angle: 90)

        // The shield contains a network hub: one place for several VPN clients.
        let shield = NSBezierPath()
        shield.move(to: NSPoint(x: p * 0.50, y: p * 0.80))
        shield.curve(to: NSPoint(x: p * 0.76, y: p * 0.70),
                     controlPoint1: NSPoint(x: p * 0.60, y: p * 0.74),
                     controlPoint2: NSPoint(x: p * 0.68, y: p * 0.71))
        shield.line(to: NSPoint(x: p * 0.76, y: p * 0.49))
        shield.curve(to: NSPoint(x: p * 0.50, y: p * 0.20),
                     controlPoint1: NSPoint(x: p * 0.76, y: p * 0.35),
                     controlPoint2: NSPoint(x: p * 0.62, y: p * 0.25))
        shield.curve(to: NSPoint(x: p * 0.24, y: p * 0.49),
                     controlPoint1: NSPoint(x: p * 0.38, y: p * 0.25),
                     controlPoint2: NSPoint(x: p * 0.24, y: p * 0.35))
        shield.line(to: NSPoint(x: p * 0.24, y: p * 0.70))
        shield.curve(to: NSPoint(x: p * 0.50, y: p * 0.80),
                     controlPoint1: NSPoint(x: p * 0.32, y: p * 0.71),
                     controlPoint2: NSPoint(x: p * 0.40, y: p * 0.74))
        shield.close()
        NSColor.white.setFill()
        shield.fill()

        navy.setStroke()
        let connections = NSBezierPath()
        connections.lineWidth = max(1, p * 0.032)
        connections.lineCapStyle = .round
        let points = [NSPoint(x: p * 0.5, y: p * 0.66),
                      NSPoint(x: p * 0.37, y: p * 0.42),
                      NSPoint(x: p * 0.63, y: p * 0.42)]
        for point in points {
            connections.move(to: NSPoint(x: p * 0.5, y: p * 0.51))
            connections.line(to: point)
        }
        connections.stroke()
        navy.setFill()
        for point in points + [NSPoint(x: p * 0.5, y: p * 0.51)] {
            NSBezierPath(ovalIn: NSRect(x: point.x - p * 0.045, y: point.y - p * 0.045,
                                       width: p * 0.09, height: p * 0.09)).fill()
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
