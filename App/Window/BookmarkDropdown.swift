import AppKit
import BrowserKit
import SwiftUI

/// A bookmark folder's contents dropped below its bar button, with favicons; subfolders cascade
/// beside their row. Like a menu it never takes key: the browser window stays key while a local
/// event monitor drives ↑/↓/→/←/↩/Esc, right-clicks and row drags, and closes the dropdown on any
/// click outside it. Each list follows the library live, so it stays open as its bookmarks change.
@MainActor
final class BookmarkDropdown {
    static let rowHeight: CGFloat = 28
    static let padding: CGFloat = 6
    private static let width: CGFloat = 280
    private static let gap: CGFloat = 4

    private let library: BookmarkLibrary
    private let onOpen: (URL, _ newTab: Bool) -> Void
    /// The open lists, outermost first; each one after the first is a subfolder of the one before.
    private var levels: [DropdownLevel] = []
    private weak var anchor: NSView?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    /// The row the mouse went down on, which a drag from there picks up.
    private var press: (level: DropdownLevel, index: Int, location: NSPoint)?

    /// Called whenever the dropdown closes, however it closed.
    var onClose: (() -> Void)?

    init(library: BookmarkLibrary, onOpen: @escaping (URL, _ newTab: Bool) -> Void) {
        self.library = library
        self.onOpen = onOpen
    }

    var isOpen: Bool { !levels.isEmpty }

    /// Shows the bookmarks in `folder` (nil for the bar's own), skipping the first `offset` of them,
    /// below `anchor`, left-aligned with it, or right-aligned with `alignRight`.
    func show(folder: Int64?, from offset: Int = 0, below anchor: NSView, alignRight: Bool = false) {
        close()
        guard let window = anchor.window, let screen = window.screen ?? NSScreen.main else { return }
        self.anchor = anchor
        let button = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = screen.visibleFrame
        let level = DropdownLevel(library: library, parentID: folder, offset: offset, depth: 0)
        let height = min(level.contentHeight, button.minY - Self.gap - visible.minY)
        let x = min(max(alignRight ? button.maxX - Self.width : button.minX, visible.minX), visible.maxX - Self.width)
        present(level, frame: NSRect(x: x, y: button.minY - Self.gap - height, width: Self.width, height: height), in: window)
        startMonitoring(window)
    }

    func close() {
        guard isOpen else { return }
        closeLevels(after: -1)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        anchor = nil
        press = nil
        onClose?()
    }

    /// Closes the dropdown when the view it opened from has left the window.
    func closeIfAnchorRemoved() {
        if anchor?.window == nil { close() }
    }

    // MARK: Levels

    private func present(_ level: DropdownLevel, frame: NSRect, in window: NSWindow) {
        let panel = dropdownPanel()
        panel.contentView = DropdownContentView(level: level, library: library, list: DropdownList(
            level: level,
            onHover: { [weak self, weak level] index in if let level { self?.hover(index, in: level) } },
            onActivate: { [weak self, weak level] index in
                if let level { self?.activate(index, in: level, newTab: NSApp.currentEvent?.modifierFlags.contains(.command) ?? false) }
            },
            onItemsChange: { [weak self, weak level] in if let level { self?.itemsChanged(in: level) } }
        ))
        level.panel = panel
        levels.append(level)
        window.addChildWindow(panel, ordered: .above)
        panel.setFrame(frame, display: true)
        panel.orderFront(nil)
    }

    /// Closes every level deeper than `depth`.
    private func closeLevels(after depth: Int) {
        while levels.count > depth + 1, let level = levels.popLast(), let panel = level.panel {
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
        }
    }

    /// A list's bookmarks changed: deeper levels may hang off a row that moved, so they close, and the
    /// panel grows or shrinks from its top edge to fit.
    private func itemsChanged(in level: DropdownLevel) {
        guard levels.contains(where: { $0 === level }) else { return }
        level.loadIcons()
        if let index = level.selectedIndex, level.item(at: index) == nil { level.selectedIndex = nil }
        closeLevels(after: level.depth)
        guard let panel = level.panel, let visible = (panel.screen ?? NSScreen.main)?.visibleFrame else { return }
        var frame = panel.frame
        frame.size.height = min(level.contentHeight, frame.maxY - visible.minY)
        frame.origin.y = panel.frame.maxY - frame.height
        panel.setFrame(frame, display: true)
    }

    /// Opens the folder at `index` beside its row, replacing any deeper level.
    private func openFolder(at index: Int, in level: DropdownLevel, selectFirst: Bool) {
        guard let folder = level.item(at: index) else { return }
        if levels.indices.contains(level.depth + 1), levels[level.depth + 1].parentID == folder.id {
            if selectFirst { levels[level.depth + 1].selectFirst() }
            return
        }
        closeLevels(after: level.depth)
        guard let window = anchor?.window, let parent = level.panel,
              let visible = (parent.screen ?? NSScreen.main)?.visibleFrame else { return }
        let child = DropdownLevel(library: library, parentID: folder.id, offset: 0, depth: level.depth + 1)
        let height = min(child.contentHeight, visible.height)
        // The child's first row lines up with the folder's row; rows report frames top-down in the panel.
        let rowTop = parent.frame.maxY - (level.rowFrames[index]?.minY ?? Self.padding + CGFloat(index) * Self.rowHeight)
        let y = max(rowTop + Self.padding - height, visible.minY)
        var x = parent.frame.maxX - 2
        if x + Self.width > visible.maxX { x = parent.frame.minX - Self.width + 2 }
        present(child, frame: NSRect(x: x, y: y, width: Self.width, height: height), in: window)
        if selectFirst { child.selectFirst() }
    }

    private func hover(_ index: Int, in level: DropdownLevel) {
        level.selectedIndex = index
        if level.item(at: index)?.isFolder == true {
            openFolder(at: index, in: level, selectFirst: false)
        } else {
            closeLevels(after: level.depth)
        }
    }

    private func activate(_ index: Int, in level: DropdownLevel, newTab: Bool) {
        guard let bookmark = level.item(at: index) else { return }
        if bookmark.isFolder {
            openFolder(at: index, in: level, selectFirst: true)
        } else if let url = bookmark.url.flatMap(URL.init(string:)) {
            close()
            onOpen(url, newTab)
        }
    }

    // MARK: Events

    private func startMonitoring(_ window: NSWindow) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseDragged, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            switch event.type {
            case .keyDown: return key(event)
            case .leftMouseDragged: return drag(event)
            default: return click(event)
            }
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        }
    }

    /// A click outside the dropdown closes it. A click on the button that opened it is swallowed,
    /// so the button toggles the dropdown instead of reopening it. A right-click on a row opens its
    /// context menu; a left press on one is remembered for `drag`.
    private func click(_ event: NSEvent) -> NSEvent? {
        if let level = levels.first(where: { $0.panel === event.window }) {
            let index = (event.window?.contentView).flatMap { level.row(at: $0.convert(event.locationInWindow, from: nil)) }
            press = nil
            if event.type == .rightMouseDown || event.modifierFlags.contains(.control) {
                if let index { showContextMenu(for: index, in: level, with: event) }
                return nil
            }
            if event.type == .leftMouseDown, let index { press = (level, index, event.locationInWindow) }
            return event
        }
        let onAnchor = anchor.map { $0.window === event.window && $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) } ?? false
        close()
        return onAnchor && event.type == .leftMouseDown ? nil : event
    }

    /// Dragging a pressed row a few points picks its bookmark up, to drop elsewhere in the dropdown or on the bar.
    private func drag(_ event: NSEvent) -> NSEvent? {
        guard let press, event.window === press.level.panel, let view = event.window?.contentView,
              BookmarkDrag.isDrag(from: press.location, to: event.locationInWindow) else { return event }
        self.press = nil
        guard let bookmark = press.level.item(at: press.index), let row = press.level.rowFrames[press.index] else { return event }
        let icon = DropdownLevel.host(bookmark).flatMap { press.level.icons[$0] }
        BookmarkDrag.begin(bookmark, icon: icon.map { FaviconContrast.displayImage($0, for: view.effectiveAppearance) },
                           from: view, at: row.origin, event: event)
        return nil
    }

    private func showContextMenu(for index: Int, in level: DropdownLevel, with event: NSEvent) {
        guard let bookmark = level.item(at: index), let anchor, let view = level.panel?.contentView else { return }
        level.selectedIndex = index
        let menu = BookmarkMenus.contextMenu(for: bookmark, library: library, in: anchor) { [weak self] url, newTab in
            self?.close()
            self?.onOpen(url, newTab)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    /// Keys act on the deepest open level; any other key closes the dropdown and goes on to the window.
    private func key(_ event: NSEvent) -> NSEvent? {
        guard event.window === anchor?.window, let level = levels.last else { return event }
        switch (event.keyCode, event.specialKey) {
        case (53, _):
            close()
        case (_, .downArrow?):
            level.moveSelection(by: 1)
        case (_, .upArrow?):
            level.moveSelection(by: -1)
        case (_, .rightArrow?):
            if let index = level.selectedIndex, level.item(at: index)?.isFolder == true { openFolder(at: index, in: level, selectFirst: true) }
        case (_, .leftArrow?):
            if level.depth > 0 { closeLevels(after: level.depth - 1) }
        case (_, .carriageReturn?), (_, .enter?):
            if let index = level.selectedIndex { activate(index, in: level, newTab: event.modifierFlags.contains(.command)) }
        default:
            close()
            return event
        }
        return nil
    }
}

/// One open list: a folder's bookmarks, read live from the library, the highlighted row, the
/// pending drop, and their favicons.
@MainActor @Observable
private final class DropdownLevel {
    let depth: Int
    /// The folder listed, or nil for the bar's own bookmarks. The list starts `offset` bookmarks in,
    /// which for the bar's overflow skips the ones still showing on the bar.
    let parentID: Int64?
    let offset: Int
    var selectedIndex: Int?
    var dropTarget: BookmarkDrag.Target?
    private(set) var icons: [String: NSImage] = [:]
    @ObservationIgnored private let library: BookmarkLibrary
    @ObservationIgnored private var requestedHosts: Set<String> = []
    @ObservationIgnored var panel: NSPanel?
    /// Row frames in the panel's top-down coordinates, for placing a subfolder beside its row.
    @ObservationIgnored var rowFrames: [Int: CGRect] = [:]

    init(library: BookmarkLibrary, parentID: Int64?, offset: Int, depth: Int) {
        self.library = library
        self.parentID = parentID
        self.offset = offset
        self.depth = depth
        loadIcons()
    }

    var items: [Bookmark] { Array(library.children(of: parentID).dropFirst(offset)) }

    func item(at index: Int) -> Bookmark? {
        let items = items
        return items.indices.contains(index) ? items[index] : nil
    }

    /// The row under `point`, in the panel's top-down coordinates.
    func row(at point: CGPoint) -> Int? {
        items.indices.first { rowFrames[$0]?.contains(point) == true }
    }

    /// Fetches the favicons of bookmarks not yet asked for.
    func loadIcons() {
        for host in Set(items.compactMap(Self.host)).subtracting(requestedHosts) {
            requestedHosts.insert(host)
            Task { [weak self] in
                guard let data = await AppServices.shared.favicons.cached(host: host),
                      let image = AppServices.image(data) else { return }
                self?.icons[host] = image
            }
        }
    }

    static func host(_ bookmark: Bookmark) -> String? {
        DisplayURL(bookmark.url.flatMap(URL.init(string:)))?.host
    }

    var contentHeight: CGFloat { CGFloat(max(items.count, 1)) * BookmarkDropdown.rowHeight + BookmarkDropdown.padding * 2 }

    func selectFirst() {
        selectedIndex = items.isEmpty ? nil : 0
    }

    func moveSelection(by step: Int) {
        let count = items.count
        guard count > 0 else { return }
        selectedIndex = selectedIndex.map { ($0 + step + count) % count } ?? (step > 0 ? 0 : count - 1)
    }
}

/// A level's panel content: the SwiftUI list, and the drop target for bookmarks dragged over it.
/// Flipped, so its coordinates match the rows' top-down frames.
private final class DropdownContentView: NSView {
    private let level: DropdownLevel
    private let library: BookmarkLibrary

    init(level: DropdownLevel, library: BookmarkLibrary, list: some View) {
        self.level = level
        self.library = library
        super.init(frame: .zero)
        let hosting = NSHostingView(rootView: list)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        addSubview(hosting)
        registerForDraggedTypes([BookmarkDrag.type])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let dragged = BookmarkDrag.bookmark(in: sender, library: library),
              library.canMove(dragged, into: level.parentID) else {
            level.dropTarget = nil
            return []
        }
        let items = level.items
        let spans = items.indices.compactMap { level.rowFrames[$0].map { $0.minY...$0.maxY } }
        level.dropTarget = BookmarkDrag.target(at: convert(sender.draggingLocation, from: nil).y, spans: spans,
                                               items: items, dragging: dragged)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        level.dropTarget = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { level.dropTarget = nil }
        guard let target = level.dropTarget, let dragged = BookmarkDrag.bookmark(in: sender, library: library) else { return false }
        BookmarkDrag.drop(dragged, on: target, in: level.parentID, library: library)
        return true
    }
}

private struct DropdownList: View {
    let level: DropdownLevel
    var onHover: (Int) -> Void
    var onActivate: (Int) -> Void
    var onItemsChange: () -> Void

    var body: some View {
        let items = level.items
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.offset) { index, bookmark in
                        DropdownRow(bookmark: bookmark, icon: DropdownLevel.host(bookmark).flatMap { level.icons[$0] },
                                    isSelected: index == level.selectedIndex || level.dropTarget == .into(bookmark))
                            .overlay(alignment: .top) { if level.dropTarget == .before(bookmark) { DropLine() } }
                            .overlay(alignment: .bottom) {
                                if index == items.count - 1, level.dropTarget == .before(nil) { DropLine(offset: 1) }
                            }
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(index) }
                            .onHover { inside in if inside { onHover(index) } }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { level.rowFrames[index] = $0 }
                    }
                    if items.isEmpty {
                        Text("No Bookmarks")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(nsColor: Theme.textTertiary))
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: BookmarkDropdown.rowHeight, alignment: .leading)
                            .overlay(alignment: .top) { if level.dropTarget != nil { DropLine() } }
                    }
                }
                .padding(BookmarkDropdown.padding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: level.selectedIndex) { _, index in
                if let index { proxy.scrollTo(index) }
            }
            .onChange(of: items) { onItemsChange() }
        }
        .dropdownSurface()
        .accessibilityElement(children: .contain)
    }
}

/// Where a dragged bookmark will land, on the edge between two rows.
private struct DropLine: View {
    var offset: CGFloat = -1

    var body: some View {
        Capsule()
            .fill(Color(nsColor: Theme.accent))
            .frame(height: 2)
            .padding(.horizontal, 4)
            .offset(y: offset)
            .allowsHitTesting(false)
    }
}

private struct DropdownRow: View {
    let bookmark: Bookmark
    let icon: NSImage?
    let isSelected: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            iconView
                .frame(width: 16, height: 16)
            Text(title)
                .font(.system(size: 13))
                .foregroundStyle(Color(nsColor: Theme.textPrimary))
                .lineLimit(1)
            Spacer(minLength: 8)
            if bookmark.isFolder {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Theme.textTertiary))
            }
        }
        .padding(.horizontal, 8)
        .frame(height: BookmarkDropdown.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(isSelected ? Color(nsColor: Theme.hoverFill) : .clear)
        )
        .help(bookmark.url ?? bookmark.title)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bookmark.isFolder ? "\(title), folder" : title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var title: String { bookmark.title.isEmpty ? (bookmark.url ?? "") : bookmark.title }

    @ViewBuilder private var iconView: some View {
        if let icon, let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) {
            // Template-tinted when FaviconContrast turns a dark glyph light for dark chrome.
            Image(nsImage: FaviconContrast.displayImage(icon, for: appearance))
                .resizable()
                .interpolation(.high)
                .foregroundStyle(Color(nsColor: Theme.textSecondary))
        } else {
            Image(systemName: bookmark.isFolder ? "folder" : "globe")
                .font(.system(size: 12))
                .foregroundStyle(Color(nsColor: Theme.textSecondary))
        }
    }
}
