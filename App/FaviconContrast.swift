import AppKit

/// Many sites ship a black monochrome favicon (GitHub, docs.rs) that disappears on a dark
/// strip. Such icons are drawn as a template in the secondary text color in dark appearance.
@MainActor
enum FaviconContrast {
    // Weak keys: an address-keyed cache would hand a freed icon's verdict to a new icon.
    private static let verdicts = NSMapTable<NSImage, NSNumber>.weakToStrongObjects()
    private static let rasters = NSMapTable<NSImage, NSImage>.weakToStrongObjects()

    /// The image to show for `icon` under `appearance`.
    static func displayImage(_ icon: NSImage, for appearance: NSAppearance) -> NSImage {
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        // Template icons (native pages) are already tinted by the view.
        guard isDark, !icon.isTemplate else { return icon }
        // SVG favicons can carry their own dark variant (docs.rs draws only a thin ring);
        // judge and tint the light rendering so every icon keeps its full shape.
        let light = lightRaster(icon)
        guard isDarkMonochrome(light) else { return icon }
        light.isTemplate = true
        return light
    }

    /// The icon drawn under the light appearance into a bitmap at 2x.
    private static func lightRaster(_ icon: NSImage) -> NSImage {
        if let cached = rasters.object(forKey: icon) { return cached.copy() as! NSImage }
        let size = icon.size
        let raster = NSImage(size: size)
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                                      bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
                icon.draw(in: NSRect(origin: .zero, size: size))
            }
            NSGraphicsContext.restoreGraphicsState()
            raster.addRepresentation(rep)
        }
        rasters.setObject(raster, forKey: icon)
        return raster.copy() as! NSImage
    }

    private static func isDarkMonochrome(_ icon: NSImage) -> Bool {
        if let known = verdicts.object(forKey: icon) { return known.boolValue }
        let result = measure(icon)
        verdicts.setObject(NSNumber(value: result), forKey: icon)
        return result
    }

    /// Mean luminance and colorfulness of the icon's opaque pixels at 16×16.
    private static func measure(_ icon: NSImage) -> Bool {
        let size = 16
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let cg = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return false }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return false }
        var luminance = 0.0, chroma = 0.0, count = 0.0
        for index in stride(from: 0, to: size * size * 4, by: 4) {
            let alpha = Double(data[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            let r = Double(data[index]) / 255 / alpha, g = Double(data[index + 1]) / 255 / alpha, b = Double(data[index + 2]) / 255 / alpha
            luminance += 0.2126 * r + 0.7152 * g + 0.0722 * b
            chroma += max(r, g, b) - min(r, g, b)
            count += 1
        }
        // Only glyph-on-transparent icons; a filled square (MDN) carries its own contrast.
        guard count > 8, count / Double(size * size) < 0.7 else { return false }
        return luminance / count < 0.22 && chroma / count < 0.15
    }
}
