import AppKit
import SwiftUI

/// GitHub avatars, fetched once each and kept in memory, so list rows draw them without flicker.
@MainActor
final class AvatarCache {
    static let shared = AvatarCache()

    private let images = NSCache<NSURL, NSImage>()
    private var loads: [URL: Task<NSImage?, Never>] = [:]

    func cached(_ url: URL) -> NSImage? { images.object(forKey: url as NSURL) }

    func load(_ url: URL) async -> NSImage? {
        if let image = cached(url) { return image }
        if let load = loads[url] { return await load.value }
        let load = Task<NSImage?, Never> {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            return NSImage(data: data)
        }
        loads[url] = load
        let image = await load.value
        loads[url] = nil
        if let image { images.setObject(image, forKey: url as NSURL) }
        return image
    }
}

/// A round avatar with a hairline ring; a field-well disc until the image arrives.
struct AvatarView: View {
    let url: URL?
    var size: CGFloat = 16
    @State private var loaded: NSImage?

    var body: some View {
        let image = loaded ?? url.flatMap(AvatarCache.shared.cached)
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Color(nsColor: Theme.fieldFill)
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Color(nsColor: Theme.hairline), lineWidth: 1) }
        .accessibilityHidden(true)
        .task(id: url) {
            guard let url, AvatarCache.shared.cached(url) == nil else { return }
            loaded = await AvatarCache.shared.load(url)
        }
    }
}
