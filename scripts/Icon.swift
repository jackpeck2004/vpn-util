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
        NSColor(calibratedRed: 0.12, green: 0.40, blue: 0.57, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: p * 0.06, y: p * 0.06, width: p * 0.88, height: p * 0.88),
                     xRadius: p * 0.20, yRadius: p * 0.20).fill()
        NSColor.white.setStroke()
        let connections = NSBezierPath()
        connections.lineWidth = max(1, p * 0.045)
        connections.lineCapStyle = .round
        let points = [NSPoint(x: p * 0.5, y: p * 0.72),
                      NSPoint(x: p * 0.29, y: p * 0.30),
                      NSPoint(x: p * 0.71, y: p * 0.30)]
        for point in points {
            connections.move(to: NSPoint(x: p * 0.5, y: p * 0.48))
            connections.line(to: point)
        }
        connections.stroke()
        NSColor.white.setFill()
        for point in points + [NSPoint(x: p * 0.5, y: p * 0.48)] {
            NSBezierPath(ovalIn: NSRect(x: point.x - p * 0.075, y: point.y - p * 0.075,
                                       width: p * 0.15, height: p * 0.15)).fill()
        }
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!
            .write(to: directory.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
