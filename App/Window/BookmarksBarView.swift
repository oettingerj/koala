import AppKit
import BrowserKit

/// Optional third chrome row: bookmarks and folders on the bar, overflow behind a chevron.
final class BookmarksBarView: NSView {
    static let height: CGFloat = 28

    private let library: BookmarkLibrary
    private var buttons: [BookmarkButton] = []
    private lazy var overflowButton = IconButton(symbol: "chevron.right.2", label: "More Bookmarks", pointSize: 10,
                                                 action: #selector(showOverflow), target: self)
    private let hairline = CALayer()
    private let emptyLabel = NSTextField(labelWithString: "Bookmark pages with ⌘D to keep them here")
    private var observation: ObservationLoop?

    /// Opens a bookmark; `newTab` when ⌘-clicked or chosen from the context menu.
    var onOpen: ((URL, _ newTab: Bool) -> Void)?

    init(library: BookmarkLibrary) {
        self.library = library
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(hairline)
        emptyLabel.font = .systemFont(ofSize: 11)
        emptyLabel.textColor = Theme.textTertiary
        addSubview(emptyLabel)
        addSubview(overflowButton)
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel("Bookmarks bar")
        observation = ObservationLoop { [weak self] in self?.sync() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = resolved(Theme.chromeSurface)
        hairline.backgroundColor = resolved(Theme.hairline)
    }

    private func sync() {
        let items = library.children(of: nil)
        buttons.forEach { $0.removeFromSuperview() }
        buttons = items.map { bookmark in
            let button = BookmarkButton(bookmark: bookmark)
            button.target = self
            button.action = #selector(pressed(_:))
            button.menu = contextMenu(for: bookmark)
            addSubview(button, positioned: .below, relativeTo: overflowButton)
            return button
        }
        emptyLabel.isHidden = !items.isEmpty
        needsLayout = true
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hairline.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2))
        CATransaction.commit()

        emptyLabel.sizeToFit()
        emptyLabel.frame.origin = NSPoint(x: 12, y: (bounds.height - emptyLabel.frame.height) / 2)

        let limit = bounds.width - 8 - Theme.iconButtonSize
        var x: CGFloat = 8
        var overflowing = false
        for button in buttons {
            let width = min(160, button.intrinsicContentSize.width)
            if x + width > limit { overflowing = true }
            button.isHidden = overflowing
            button.frame = NSRect(x: x, y: (bounds.height - 22) / 2, width: width, height: 22)
            x += width + 2
        }
        overflowButton.isHidden = !overflowing
        overflowButton.frame = NSRect(x: bounds.width - 4 - 24, y: (bounds.height - 22) / 2, width: 24, height: 22)
    }

    @objc private func pressed(_ sender: BookmarkButton) {
        if sender.bookmark.isFolder {
            let menu = BookmarkMenus.menu(for: library.children(of: sender.bookmark.id), library: library, onOpen: onOpen)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
        } else if let url = sender.bookmark.url.flatMap(URL.init(string:)) {
            onOpen?(url, NSApp.currentEvent?.modifierFlags.contains(.command) ?? false)
        }
    }

    @objc private func showOverflow() {
        let hidden = buttons.filter(\.isHidden).map(\.bookmark)
        let menu = BookmarkMenus.menu(for: hidden, library: library, onOpen: onOpen)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: overflowButton)
    }

    private func contextMenu(for bookmark: Bookmark) -> NSMenu {
        let menu = NSMenu()
        if let url = bookmark.url.flatMap(URL.init(string:)) {
            menu.addItem(closureMenuItem("Open in New Tab") { [weak self] in self?.onOpen?(url, true) })
            menu.addItem(closureMenuItem("Copy Link") { Pasteboard.copy(url: url, title: bookmark.title) })
            menu.addItem(.separator())
        }
        menu.addItem(closureMenuItem("Rename…") { [weak self] in self?.rename(bookmark) })
        let move = NSMenuItem(title: "Move To", action: nil, keyEquivalent: "")
        move.submenu = BookmarkMenus.moveMenu(for: bookmark, library: library)
        menu.addItem(move)
        menu.addItem(closureMenuItem("Delete") { [weak self] in self?.delete(bookmark) })
        menu.addItem(.separator())
        menu.addItem(closureMenuItem("New Folder…") { [weak self] in self?.newFolder() })
        return menu
    }

    /// Right-click on the bar itself, away from any bookmark.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(closureMenuItem("New Folder…") { [weak self] in self?.newFolder() })
        return menu
    }

    private func newFolder() {
        NSApp.sendAction(#selector(BrowserWindowController.newBookmarkFolder(_:)), to: nil, from: self)
    }

    private func rename(_ bookmark: Bookmark) {
        guard let window else { return }
        BookmarkMenus.promptForTitle(bookmark.isFolder ? "Rename folder" : "Rename bookmark", initial: bookmark.title,
                                     button: "Rename", in: window) { [library] title in
            Task { try? await library.rename(bookmark, to: title) }
        }
    }

    /// Deleting a folder deletes what it holds, so a non-empty folder asks first.
    private func delete(_ bookmark: Bookmark) {
        guard bookmark.isFolder, !library.children(of: bookmark.id).isEmpty, let window else {
            Task { try? await library.remove(bookmark) }
            return
        }
        let alert = NSAlert()
        alert.messageText = "Delete “\(bookmark.title)” and everything in it?"
        alert.informativeText = "The bookmarks and folders inside it are deleted too."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons[0].hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [library] response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in try? await library.remove(bookmark) }
        }
    }
}

/// A bookmark on the bar: favicon (or folder glyph) and title.
final class BookmarkButton: NSButton {
    let bookmark: Bookmark
    private var favicon: NSImage?
    private var isHovered = false { didSet { updateFill() } }
    private var tracking: NSTrackingArea?

    init(bookmark: Bookmark) {
        self.bookmark = bookmark
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        contentTintColor = Theme.textSecondary
        imagePosition = .imageLeading
        imageHugsTitle = true
        lineBreakMode = .byTruncatingTail
        toolTip = bookmark.url ?? bookmark.title
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous
        image = Self.placeholder(folder: bookmark.isFolder)
        attributedTitle = NSAttributedString(string: " " + bookmark.title, attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: Theme.textSecondary,
        ])
        if let host = DisplayURL(bookmark.url.flatMap(URL.init(string:)))?.host {
            Task { [weak self] in
                guard let data = await AppServices.shared.favicons.cached(host: host),
                      let icon = AppServices.image(data) else { return }
                icon.size = NSSize(width: 14, height: 14)
                self?.favicon = icon
                self?.applyIcon()
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += 12
        return size
    }

    private func applyIcon() {
        guard let favicon else { return }
        image = FaviconContrast.displayImage(favicon, for: effectiveAppearance)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyIcon()
        updateFill()
    }

    private static func placeholder(folder: Bool) -> NSImage? {
        NSImage(systemSymbolName: folder ? "folder" : "globe", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .regular))
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override var isHighlighted: Bool { didSet { updateFill() } }

    private func updateFill() {
        let fill: NSColor? = isHighlighted ? Theme.pressedFill : isHovered ? Theme.hoverFill : nil
        layer?.backgroundColor = fill.map(resolved) ?? .clear
    }
}

/// Menus listing bookmarks, with folders as submenus. Shared by the bar and the menu bar.
@MainActor
enum BookmarkMenus {
    /// The bar and every folder, indented by depth, as destinations for `bookmark`. The bookmark's
    /// own subtree is left out (a folder can't go inside itself) and its current place is checked.
    static func moveMenu(for bookmark: Bookmark, library: BookmarkLibrary) -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, parentID: Int64?, depth: Int) {
            let item = closureMenuItem(title) {
                let end = library.children(of: parentID).count
                Task { try? await library.move(bookmark, to: end, in: parentID) }
            }
            item.image = NSImage(systemSymbolName: parentID == nil ? "menubar.rectangle" : "folder", accessibilityDescription: nil)
            item.indentationLevel = depth
            if parentID == bookmark.parentID {
                item.state = .on
                item.action = nil
            }
            menu.addItem(item)
            for folder in library.children(of: parentID) where folder.isFolder && folder.id != bookmark.id {
                add(folder.title, parentID: folder.id, depth: depth + 1)
            }
        }
        add("Bookmarks Bar", parentID: nil, depth: 0)
        return menu
    }

    /// Asks for a bookmark or folder name in a sheet; `completion` gets the trimmed, non-empty title.
    static func promptForTitle(_ message: String, initial: String, button: String, in window: NSWindow,
                               completion: @escaping @MainActor (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        let field = NSTextField(string: initial)
        field.placeholderString = "Name"
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 22)
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            let title = field.stringValue.trimmingCharacters(in: .whitespaces)
            guard response == .alertFirstButtonReturn, !title.isEmpty else { return }
            MainActor.assumeIsolated { completion(title) }
        }
    }

    static func menu(for bookmarks: [Bookmark], library: BookmarkLibrary, onOpen: ((URL, Bool) -> Void)?) -> NSMenu {
        let menu = NSMenu()
        append(bookmarks, to: menu, library: library, onOpen: onOpen)
        return menu
    }

    static func append(_ bookmarks: [Bookmark], to menu: NSMenu, library: BookmarkLibrary, onOpen: ((URL, Bool) -> Void)?) {
        for bookmark in bookmarks {
            if bookmark.isFolder {
                let item = NSMenuItem(title: bookmark.title, action: nil, keyEquivalent: "")
                item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
                item.submenu = self.menu(for: library.children(of: bookmark.id), library: library, onOpen: onOpen)
                menu.addItem(item)
            } else if let url = bookmark.url.flatMap(URL.init(string:)) {
                let item = closureMenuItem(bookmark.title.isEmpty ? url.absoluteString : bookmark.title) {
                    onOpen?(url, NSApp.currentEvent?.modifierFlags.contains(.command) ?? false)
                }
                item.toolTip = url.absoluteString
                menu.addItem(item)
            }
        }
        if bookmarks.isEmpty {
            let empty = NSMenuItem(title: "No Bookmarks", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
        }
    }
}
