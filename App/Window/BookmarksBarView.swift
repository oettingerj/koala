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
    /// The insertion line shown while a bookmark is dragged over the bar.
    private let dropIndicator = CALayer()
    private var dropTarget: BookmarkDrag.Target? { didSet { showDropTarget() } }
    private let emptyLabel = NSTextField(labelWithString: MenuShortcuts.text(for: #selector(BrowserWindowController.toggleBookmark(_:)))
        .map { "Bookmark pages with \($0) to keep them here" } ?? "Bookmark pages to keep them here")
    private var observation: ObservationLoop?
    private lazy var dropdown: BookmarkDropdown = {
        let dropdown = BookmarkDropdown(library: library) { [weak self] url, newTab in self?.onOpen?(url, newTab) }
        dropdown.onClose = { [weak self] in self?.buttons.forEach { $0.isOpen = false } }
        return dropdown
    }()

    /// Opens a bookmark; `newTab` when ⌘-clicked or chosen from the context menu.
    var onOpen: ((URL, _ newTab: Bool) -> Void)?

    init(library: BookmarkLibrary) {
        self.library = library
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(hairline)
        dropIndicator.cornerRadius = 1
        dropIndicator.isHidden = true
        dropIndicator.zPosition = 1
        layer?.addSublayer(dropIndicator)
        registerForDraggedTypes([BookmarkDrag.type])
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
        dropIndicator.backgroundColor = resolved(Theme.accent)
    }

    private func sync() {
        let items = library.children(of: nil)
        // Changes inside folders leave the bar as it is, so an open dropdown stays open through them.
        guard items != buttons.map(\.bookmark) else { return }
        buttons.forEach { $0.removeFromSuperview() }
        buttons = items.map { bookmark in
            let button = BookmarkButton(bookmark: bookmark)
            button.target = self
            button.action = #selector(pressed(_:))
            button.menu = BookmarkMenus.contextMenu(for: bookmark, library: library, in: self) { [weak self] in self?.onOpen?($0, $1) }
            addSubview(button, positioned: .below, relativeTo: overflowButton)
            return button
        }
        dropdown.closeIfAnchorRemoved()
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
            dropdown.show(folder: sender.bookmark.id, below: sender)
            sender.isOpen = true
        } else if let url = sender.bookmark.url.flatMap(URL.init(string:)) {
            onOpen?(url, NSApp.currentEvent?.modifierFlags.contains(.command) ?? false)
        }
    }

    @objc private func showOverflow() {
        dropdown.show(folder: nil, from: buttons.prefix { !$0.isHidden }.count, below: overflowButton, alignRight: true)
    }

    // MARK: Dropping

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let dragged = BookmarkDrag.bookmark(in: sender, library: library) else {
            dropTarget = nil
            return []
        }
        let visible = buttons.prefix { !$0.isHidden }
        dropTarget = BookmarkDrag.target(at: convert(sender.draggingLocation, from: nil).x,
                                         spans: visible.map { $0.frame.minX...$0.frame.maxX },
                                         items: buttons.map(\.bookmark), dragging: dragged)
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropTarget = nil
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { dropTarget = nil }
        guard let target = dropTarget, let dragged = BookmarkDrag.bookmark(in: sender, library: library) else { return false }
        BookmarkDrag.drop(dragged, on: target, in: nil, library: library)
        return true
    }

    /// Highlights the folder a drop goes into, or draws the insertion line in the gap before its place.
    private func showDropTarget() {
        for button in buttons { button.isDropTarget = dropTarget == .into(button.bookmark) }
        let visible = buttons.prefix { !$0.isHidden }
        var x: CGFloat?
        if case .before(let sibling) = dropTarget {
            x = visible.first { $0.bookmark == sibling }.map { $0.frame.minX - 2 } ?? (visible.last?.frame.maxX ?? 6)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dropIndicator.isHidden = x == nil
        dropIndicator.frame = NSRect(x: x ?? 0, y: (bounds.height - 18) / 2, width: 2, height: 18)
        CATransaction.commit()
    }

    /// Right-click on the bar itself, away from any bookmark.
    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(closureMenuItem("New Folder…") { [weak self, library] in
            if let window = self?.window { BookmarkMenus.newFolder(in: nil, library: library, in: window) }
        })
        return menu
    }
}

/// A bookmark on the bar: favicon (or folder glyph) and title.
final class BookmarkButton: NSButton {
    let bookmark: Bookmark
    private var favicon: NSImage?
    private var faviconRevision: Int?
    private var faviconObservation: ObservationLoop?
    private var isHovered = false { didSet { updateFill() } }
    private var tracking: NSTrackingArea?
    /// Held pressed while the folder's dropdown is open.
    var isOpen = false { didSet { updateFill() } }
    /// Held pressed while a dragged bookmark hovers to drop into this folder.
    var isDropTarget = false { didSet { updateFill() } }

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
            faviconObservation = ObservationLoop { [weak self] in self?.loadFavicon(host: host) }
        }
    }

    /// Loads the cached icon now, and again whenever a visit fetches a new one.
    private func loadFavicon(host: String) {
        let revision = AppServices.shared.faviconRevisions[host, default: 0]
        guard revision != faviconRevision else { return }
        faviconRevision = revision
        Task { [weak self] in
            guard let data = await AppServices.shared.favicons.cached(host: host),
                  let icon = AppServices.image(data) else { return }
            icon.size = NSSize(width: 14, height: 14)
            self?.favicon = icon
            self?.applyIcon()
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

    override var mouseDownCanMoveWindow: Bool { false }

    /// Tracks the press itself so that moving a few points picks the bookmark up instead of clicking it.
    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        isHighlighted = true
        defer { isHighlighted = false }
        while let next = window.nextEvent(matching: [.leftMouseUp, .leftMouseDragged]) {
            let inside = bounds.contains(convert(next.locationInWindow, from: nil))
            if next.type == .leftMouseUp {
                isHighlighted = false
                if inside { sendAction(action, to: target) }
                return
            }
            if BookmarkDrag.isDrag(from: event.locationInWindow, to: next.locationInWindow) {
                isHighlighted = false
                BookmarkDrag.begin(bookmark, icon: image, from: self, at: NSPoint(x: 0, y: (bounds.height - 22) / 2), event: next)
                return
            }
            isHighlighted = inside
        }
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override var isHighlighted: Bool { didSet { updateFill() } }

    private func updateFill() {
        let fill: NSColor? = isHighlighted || isOpen || isDropTarget ? Theme.pressedFill : isHovered ? Theme.hoverFill : nil
        layer?.backgroundColor = fill.map(resolved) ?? .clear
    }
}

/// Menus listing bookmarks, with folders as submenus, for the menu bar; and the bar's shared menus.
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

    /// The context menu for a bookmark on the bar or in a folder dropdown. Its sheets open on `view`'s window.
    static func contextMenu(for bookmark: Bookmark, library: BookmarkLibrary, in view: NSView,
                            onOpen: @escaping (URL, _ newTab: Bool) -> Void) -> NSMenu {
        let menu = NSMenu()
        if let url = bookmark.url.flatMap(URL.init(string:)) {
            menu.addItem(closureMenuItem("Open in New Tab") { onOpen(url, true) })
            menu.addItem(closureMenuItem("Copy Link") { Pasteboard.copy(url: url, title: bookmark.title) })
            menu.addItem(.separator())
        }
        menu.addItem(closureMenuItem(bookmark.isFolder ? "Rename…" : "Edit…") { [weak view] in
            if let window = view?.window { edit(bookmark, library: library, in: window) }
        })
        let move = NSMenuItem(title: "Move To", action: nil, keyEquivalent: "")
        move.submenu = moveMenu(for: bookmark, library: library)
        menu.addItem(move)
        menu.addItem(closureMenuItem("Delete") { [weak view] in delete(bookmark, library: library, in: view?.window) })
        menu.addItem(.separator())
        menu.addItem(closureMenuItem("New Folder…") { [weak view] in
            if let window = view?.window { newFolder(in: bookmark.parentID, library: library, in: window) }
        })
        return menu
    }

    /// Renames a folder, or edits a bookmark's name and address, in a sheet.
    static func edit(_ bookmark: Bookmark, library: BookmarkLibrary, in window: NSWindow) {
        guard !bookmark.isFolder else {
            return promptForTitle("Rename folder", initial: bookmark.title, button: "Rename", in: window) { title in
                Task { try? await library.rename(bookmark, to: title) }
            }
        }
        let alert = NSAlert()
        alert.messageText = "Edit bookmark"
        let title = NSTextField(string: bookmark.title)
        title.placeholderString = "Name"
        let address = NSTextField(string: bookmark.url ?? "")
        address.placeholderString = "Address"
        let fields = NSStackView(views: [title, address])
        fields.orientation = .vertical
        fields.spacing = 8
        fields.frame = NSRect(x: 0, y: 0, width: 300, height: 52)
        for field in [title, address] { field.widthAnchor.constraint(equalToConstant: 300).isActive = true }
        alert.accessoryView = fields
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = title
        alert.beginSheetModal(for: window) { response in
            let name = title.stringValue.trimmingCharacters(in: .whitespaces)
            let url = AddressInput.resolve(address.stringValue)
            guard response == .alertFirstButtonReturn, !name.isEmpty else { return }
            MainActor.assumeIsolated { _ = Task { try? await library.update(bookmark, title: name, url: url) } }
        }
    }

    /// Asks for a name, then adds a folder at the end of `parentID`'s children.
    static func newFolder(in parentID: Int64?, library: BookmarkLibrary, in window: NSWindow) {
        promptForTitle("New folder", initial: "", button: "Create", in: window) { title in
            Task { try? await library.add(title: title, url: nil, in: parentID) }
        }
    }

    /// Deleting a folder deletes what it holds, so a non-empty folder asks first.
    static func delete(_ bookmark: Bookmark, library: BookmarkLibrary, in window: NSWindow?) {
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
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            Task { @MainActor in try? await library.remove(bookmark) }
        }
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
