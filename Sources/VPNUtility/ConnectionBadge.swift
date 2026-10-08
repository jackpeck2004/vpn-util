import AppKit

/// Separate from the template glyph so macOS still supplies its native contrast.
final class ConnectionBadge: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemGreen.setFill()
        NSBezierPath(ovalIn: bounds).fill()
    }

    // Clicks on the badge continue to the status bar button underneath it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
