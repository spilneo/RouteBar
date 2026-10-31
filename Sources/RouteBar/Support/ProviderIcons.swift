import AppKit
import Observation
import RouteBarKit

/// Provider logos served by OmniRoute itself at `/providers/<id>.svg`.
@MainActor
@Observable
final class ProviderIcons {
    struct Icon {
        let image: NSImage
        /// Single-colour logos (pure black or white) are drawn as templates so they
        /// stay visible in both light and dark mode.
        let isMonochrome: Bool
    }

    static let shared = ProviderIcons()

    private(set) var icons: [String: Icon] = [:]
    private var requested: Set<String> = []
    private var client = OmniRouteClient(cliToken: nil)

    /// Loads logos from this server from now on. Logos are the same everywhere, so the cache is kept.
    func use(_ client: OmniRouteClient) {
        self.client = client
        requested = requested.filter { icons[$0] != nil }
    }

    func icon(for id: String) -> Icon? {
        if !requested.contains(id) {
            requested.insert(id)
            Task { await load(id) }
        }
        return icons[id]
    }

    private func load(_ id: String) async {
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let data = try? await client.call("GET", "/providers/\(encoded).svg"),
              let image = NSImage(data: data) else {
            requested.remove(id) // Retry next time, for example once OmniRoute is up.
            return
        }
        image.size = NSSize(width: 64, height: 64)
        icons[id] = Icon(image: image, isMonochrome: Self.isMonochrome(image))
    }

    static func isMonochrome(_ image: NSImage) -> Bool {
        let side = 24
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return false }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()

        var opaque = 0
        for x in 0..<side {
            for y in 0..<side {
                guard let color = bitmap.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
                opaque += 1
                if color.saturationComponent > 0.18 { return false }
            }
        }
        return opaque > 0
    }
}
