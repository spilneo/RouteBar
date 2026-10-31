import AppKit

/// The three-arrow mark from `logo.svg`, drawn as a menu bar template image.
@MainActor
enum MenuBarIcon {
    private static let cache = NSCache<NSNumber, NSImage>()

    static func image(active: Bool) -> NSImage {
        let key = NSNumber(value: active)
        if let cached = cache.object(forKey: key) { return cached }
        let image = draw(alpha: active ? 1 : 0.45)
        cache.setObject(image, forKey: key)
        return image
    }

    /// Same geometry as the logo's 1024-unit artboard, scaled into an 18 pt square.
    static func draw(alpha: CGFloat) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { _ in
            let bounds = (minX: 216.0, minY: 216.0, side: 592.0) // arrows plus half the stroke
            let scale = size.width / bounds.side
            let transform = NSAffineTransform()
            transform.scale(by: scale)
            transform.translateX(by: -bounds.minX, yBy: -bounds.minY)

            let path = NSBezierPath()
            let center = 512.0, spread = 228.0, trunk = 258.0, bend = 372.0, settle = 556.0
            let sideTip = 708.0, middleTip = 766.0, head = 96.0 * 0.7071
            for y in [center - spread, center + spread] {
                path.move(to: NSPoint(x: trunk, y: center))
                path.line(to: NSPoint(x: bend, y: center))
                let mid = (bend + settle) / 2
                path.curve(to: NSPoint(x: settle, y: y), controlPoint1: NSPoint(x: mid, y: center), controlPoint2: NSPoint(x: mid, y: y))
                path.line(to: NSPoint(x: sideTip, y: y))
            }
            path.move(to: NSPoint(x: trunk, y: center))
            path.line(to: NSPoint(x: middleTip, y: center))
            for (tip, y) in [(sideTip, center - spread), (middleTip, center), (sideTip, center + spread)] {
                path.move(to: NSPoint(x: tip - head, y: y - head))
                path.line(to: NSPoint(x: tip, y: y))
                path.line(to: NSPoint(x: tip - head, y: y + head))
            }
            path.transform(using: transform as AffineTransform)
            path.lineWidth = 84 * scale
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.withAlphaComponent(alpha).setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
