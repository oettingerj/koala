import AppKit
import BrowserKit

/// Dragging bookmarks to reorder them on the bar and in folder dropdowns. The pasteboard carries the
/// bookmark's id for Koala's own drop targets, and its URL so it also drops into pages and other apps.
@MainActor
enum BookmarkDrag {
    static let type = NSPasteboard.PasteboardType("com.joshoettinger.koala.bookmark")

    /// Where a dragged bookmark lands: before an item (nil for the end of the list), or inside a folder.
    enum Target: Equatable {
        case before(Bookmark?)
        case into(Bookmark)
    }

    /// Whether the mouse moved far enough from a press to pick the bookmark up rather than click it.
    static func isDrag(from start: NSPoint, to point: NSPoint) -> Bool {
        hypot(point.x - start.x, point.y - start.y) > 4
    }

    /// Starts dragging `bookmark` from `view`, its image placed at `origin` in the view's coordinates.
    static func begin(_ bookmark: Bookmark, icon: NSImage?, from view: NSView, at origin: NSPoint, event: NSEvent) {
        guard let id = bookmark.id else { return }
        let item = NSPasteboardItem()
        item.setString(String(id), forType: type)
        if let url = bookmark.url {
            item.setString(url, forType: .URL)
            item.setString(url, forType: .string)
        }
        let image = image(for: bookmark, icon: icon)
        let dragging = NSDraggingItem(pasteboardWriter: item)
        dragging.setDraggingFrame(NSRect(origin: origin, size: image.size), contents: image)
        view.beginDraggingSession(with: [dragging], event: event, source: Source.shared)
    }

    /// The bookmark being dragged, when the drag is one of Koala's bookmarks.
    static func bookmark(in info: NSDraggingInfo, library: BookmarkLibrary) -> Bookmark? {
        guard let id = info.draggingPasteboard.string(forType: type).flatMap(Int64.init) else { return nil }
        return library.all.first { $0.id == id }
    }

    /// Where a drop at `position` lands among `items`, the first of which are laid out along one axis
    /// at `spans`: into a folder over the middle half of its span, otherwise before the nearest item.
    static func target(at position: CGFloat, spans: [ClosedRange<CGFloat>], items: [Bookmark], dragging: Bookmark) -> Target {
        func item(_ index: Int) -> Bookmark? { items.indices.contains(index) ? items[index] : nil }
        for (index, span) in spans.enumerated() where position < span.upperBound {
            let inset = (span.upperBound - span.lowerBound) / 4
            if items[index].isFolder, items[index].id != dragging.id,
               position > span.lowerBound + inset, position < span.upperBound - inset {
                return .into(items[index])
            }
            return .before(item(position < (span.lowerBound + span.upperBound) / 2 ? index : index + 1))
        }
        return .before(item(spans.count))
    }

    /// Moves `bookmark` to `target` among the children of `parentID`.
    static func drop(_ bookmark: Bookmark, on target: Target, in parentID: Int64?, library: BookmarkLibrary) {
        Task {
            switch target {
            case .before(let sibling): try? await library.move(bookmark, before: sibling, in: parentID)
            case .into(let folder): try? await library.move(bookmark, to: .max, in: folder.id)
            }
        }
    }

    /// A pill of the bookmark's icon and title, like its button on the bar.
    private static func image(for bookmark: Bookmark, icon: NSImage?) -> NSImage {
        let title = NSAttributedString(string: bookmark.title.isEmpty ? bookmark.url ?? "" : bookmark.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.textPrimary,
        ])
        let titleSize = title.size()
        let titleWidth = min(ceil(titleSize.width), 200)
        let icon = icon ?? NSImage(systemSymbolName: bookmark.isFolder ? "folder" : "globe", accessibilityDescription: nil)
        return NSImage(size: NSSize(width: 34 + titleWidth, height: 22), flipped: false) { rect in
            let pill = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
            Theme.chromeSurface.setFill()
            pill.fill()
            Theme.hairline.setStroke()
            pill.stroke()
            if let icon {
                tinted(icon).draw(in: NSRect(x: 8, y: 4, width: 14, height: 14))
            }
            title.draw(with: NSRect(x: 26, y: (rect.height - titleSize.height) / 2, width: titleWidth, height: titleSize.height),
                       options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
            return true
        }
    }

    /// Template images (symbols, and favicons FaviconContrast turned into glyphs) in the bar's icon color.
    private static func tinted(_ icon: NSImage) -> NSImage {
        guard icon.isTemplate else { return icon }
        return NSImage(size: icon.size, flipped: false) { rect in
            icon.draw(in: rect)
            Theme.textSecondary.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    private final class Source: NSObject, NSDraggingSource {
        static let shared = Source()

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .withinApplication ? [.move, .copy, .link] : [.copy, .link]
        }
    }
}
