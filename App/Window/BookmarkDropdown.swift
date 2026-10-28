import AppKit
import BrowserKit
import SwiftUI

/// A bookmark folder's contents dropped below its bar button, with favicons; subfolders cascade
/// beside their row. Like a menu it never takes key: the browser window stays key while a local
/// event monitor drives ↑/↓/→/←/↩/Esc and closes the dropdown on any click outside it.
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

    /// Called whenever the dropdown closes, however it closed.
    var onClose: (() -> Void)?

    init(library: BookmarkLibrary, onOpen: @escaping (URL, _ newTab: Bool) -> Void) {
        self.library = library
        self.onOpen = onOpen
    }

    var isOpen: Bool { !levels.isEmpty }

    /// Shows `bookmarks` below `anchor`, left-aligned with it, or right-aligned with `alignRight`.
    func show(_ bookmarks: [Bookmark], below anchor: NSView, alignRight: Bool = false) {
        close()
        guard let window = anchor.window, let screen = window.screen ?? NSScreen.main else { return }
        self.anchor = anchor
        let button = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = screen.visibleFrame
        let level = DropdownLevel(items: bookmarks, depth: 0)
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
        onClose?()
    }

    // MARK: Levels

    private func present(_ level: DropdownLevel, frame: NSRect, in window: NSWindow) {
        let panel = dropdownPanel()
        panel.contentView = NSHostingView(rootView: DropdownList(
            level: level,
            onHover: { [weak self, weak level] index in if let level { self?.hover(index, in: level) } },
            onActivate: { [weak self, weak level] index in
                if let level { self?.activate(index, in: level, newTab: NSApp.currentEvent?.modifierFlags.contains(.command) ?? false) }
            }
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

    /// Opens the folder at `index` beside its row, replacing any deeper level.
    private func openFolder(at index: Int, in level: DropdownLevel, selectFirst: Bool) {
        let folder = level.items[index]
        if levels.indices.contains(level.depth + 1), levels[level.depth + 1].folderID == folder.id {
            if selectFirst { levels[level.depth + 1].selectFirst() }
            return
        }
        closeLevels(after: level.depth)
        guard let window = anchor?.window, let parent = level.panel,
              let visible = (parent.screen ?? NSScreen.main)?.visibleFrame else { return }
        let child = DropdownLevel(items: library.children(of: folder.id), depth: level.depth + 1, folderID: folder.id)
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
        if level.items[index].isFolder {
            openFolder(at: index, in: level, selectFirst: false)
        } else {
            closeLevels(after: level.depth)
        }
    }

    private func activate(_ index: Int, in level: DropdownLevel, newTab: Bool) {
        let bookmark = level.items[index]
        if bookmark.isFolder {
            openFolder(at: index, in: level, selectFirst: true)
        } else if let url = bookmark.url.flatMap(URL.init(string:)) {
            close()
            onOpen(url, newTab)
        }
    }

    // MARK: Events

    private func startMonitoring(_ window: NSWindow) {
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            return event.type == .keyDown ? key(event) : click(event)
        }
        for name in [NSWindow.didResignKeyNotification, NSWindow.didResizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.close() }
            })
        }
    }

    /// A click outside the dropdown closes it. A click on the button that opened it is swallowed,
    /// so the button toggles the dropdown instead of reopening it.
    private func click(_ event: NSEvent) -> NSEvent? {
        if levels.contains(where: { $0.panel === event.window }) { return event }
        let onAnchor = anchor.map { $0.window === event.window && $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) } ?? false
        close()
        return onAnchor && event.type == .leftMouseDown ? nil : event
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
            if let index = level.selectedIndex, level.items[index].isFolder { openFolder(at: index, in: level, selectFirst: true) }
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

/// One open list: a folder's bookmarks, the highlighted row, and their favicons.
@MainActor @Observable
private final class DropdownLevel {
    let items: [Bookmark]
    let depth: Int
    let folderID: Int64?
    var selectedIndex: Int?
    private(set) var icons: [String: NSImage] = [:]
    @ObservationIgnored var panel: NSPanel?
    /// Row frames in the panel's top-down coordinates, for placing a subfolder beside its row.
    @ObservationIgnored var rowFrames: [Int: CGRect] = [:]

    init(items: [Bookmark], depth: Int, folderID: Int64? = nil) {
        self.items = items
        self.depth = depth
        self.folderID = folderID
        for host in Set(items.compactMap(Self.host)) {
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
        guard !items.isEmpty else { return }
        selectedIndex = selectedIndex.map { ($0 + step + items.count) % items.count } ?? (step > 0 ? 0 : items.count - 1)
    }
}

private struct DropdownList: View {
    let level: DropdownLevel
    var onHover: (Int) -> Void
    var onActivate: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(level.items.enumerated()), id: \.offset) { index, bookmark in
                        DropdownRow(bookmark: bookmark, icon: DropdownLevel.host(bookmark).flatMap { level.icons[$0] },
                                    isSelected: index == level.selectedIndex)
                            .id(index)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(index) }
                            .onHover { inside in if inside { onHover(index) } }
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { level.rowFrames[index] = $0 }
                    }
                    if level.items.isEmpty {
                        Text("No Bookmarks")
                            .font(.system(size: 13))
                            .foregroundStyle(Color(nsColor: Theme.textTertiary))
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, minHeight: BookmarkDropdown.rowHeight, alignment: .leading)
                    }
                }
                .padding(BookmarkDropdown.padding)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: level.selectedIndex) { _, index in
                if let index { proxy.scrollTo(index) }
            }
        }
        .dropdownSurface()
        .accessibilityElement(children: .contain)
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
