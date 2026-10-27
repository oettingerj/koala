import AppKit
import BrowserKit
import WebKit

/// One browser window: tab strip in the titlebar, toolbar, and the selected tab's page.
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let tabs = TabCollection()
    private let rootView: BrowserRootView
    private var selectionObservation: ObservationLoop?
    private var sessionObservation: ObservationLoop?
    private var bookmarkObservation: ObservationLoop?
    private lazy var commandBar: CommandBar = {
        let bar = CommandBar(engine: services.suggestions)
        bar.onActivate = { [weak self] row, _ in self?.activate(row, inNewTab: true) }
        return bar
    }()
    private lazy var addressDropdown: AddressDropdown = {
        let dropdown = AddressDropdown(engine: services.suggestions)
        dropdown.onActivate = { [weak self] row, newTab in self?.activate(row, inNewTab: newTab) }
        return dropdown
    }()
    private var services: AppServices { .shared }
    var onClose: ((BrowserWindowController) -> Void)?

    /// Opens a window with one tab at `initialURL` (blank when nil), or the tabs of `snapshot`.
    init(initialURL: URL? = nil, snapshot: WindowSnapshot? = nil) {
        rootView = BrowserRootView(tabs: tabs)
        let window = BrowserWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // An empty compact toolbar gives the titlebar the strip's 40pt height and centers the
        // traffic lights in it, natively, without repositioning the window buttons.
        window.toolbar = NSToolbar(identifier: "NanoTitlebar")
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 480, height: 320)
        window.contentView = rootView
        window.tabbingMode = .disallowed
        // AppKit would otherwise focus the first text field (the address field) on show.
        window.initialFirstResponder = nil
        window.autorecalculatesKeyViewLoop = false
        super.init(window: window)
        window.delegate = self
        if let frame = snapshot?.frame {
            window.setFrame(frame, display: false)
        } else {
            window.setFrameAutosaveName("NanoBrowserWindow")
        }

        rootView.strip.onSelect = { [weak self] tab in self?.tabs.select(tab) }
        rootView.strip.onClose = { [weak self] tab in self?.close(tab) }
        rootView.strip.menuForTab = { [weak self] tab in self?.contextMenu(for: tab) }
        rootView.toolbar.addressField.onSubmit = { [weak self] text in self?.navigate(to: text) }
        rootView.toolbar.addressField.onCancel = { [weak self] in self?.focusPage() }
        rootView.toolbar.addressField.onToggleBookmark = { [weak self] in self?.toggleBookmark(nil) }
        let field = rootView.toolbar.addressField
        field.onTextChange = { [weak self, weak field] text in
            guard let self, let field else { return }
            addressDropdown.update(query: text, anchor: field)
        }
        field.onMoveSelection = { [weak self] step in self?.addressDropdown.moveSelection(by: step) ?? false }
        field.onSubmitSelection = { [weak self] newTab in self?.addressDropdown.activateSelected(newTab: newTab) ?? false }
        field.onEndEditing = { [weak self] in self?.addressDropdown.hide() }
        rootView.bookmarksBar.onOpen = { [weak self] url, newTab in self?.openBookmark(url, newTab: newTab) }

        if let snapshot, !snapshot.tabs.isEmpty {
            for tabSnapshot in snapshot.tabs {
                let tab = Tab(snapshot: tabSnapshot)
                tab.delegate = self
                tabs.insert(tab, select: false)
                services.applyCachedFavicon(to: tab)
            }
            tabs.select(at: snapshot.selectedIndex ?? 0)
        } else {
            openTab(url: initialURL, select: true)
            if initialURL == nil { focusAddressField() }
        }

        selectionObservation = ObservationLoop { [weak self] in self?.showSelectedTab() }
        sessionObservation = ObservationLoop { [weak self] in self?.observeSessionState() }
        bookmarkObservation = ObservationLoop { [weak self] in self?.updateBookmarkStar() }
    }

    private func updateBookmarkStar() {
        let url = tabs.selected?.url
        let field = rootView.toolbar.addressField
        field.canBookmark = url.map { $0.scheme == "http" || $0.scheme == "https" } ?? false
        field.isBookmarked = url.flatMap { services.bookmarks.bookmark(for: $0) } != nil
    }

    func openBookmark(_ url: URL, newTab: Bool) {
        if newTab {
            openTab(url: url, select: false, opener: nil)
        } else if let tab = tabs.selected {
            tab.load(url)
            focusPage()
        } else {
            openTab(url: url, select: true)
        }
    }

    @objc func toggleBookmark(_ sender: Any?) {
        guard let tab = tabs.selected, let url = tab.url, url.scheme == "http" || url.scheme == "https" else { return }
        let library = services.bookmarks
        Task {
            if let existing = library.bookmark(for: url) {
                try? await library.remove(existing)
            } else {
                try? await library.add(title: tab.displayTitle, url: url)
            }
        }
    }

    @objc func toggleBookmarksBar(_ sender: Any?) {
        rootView.showsBookmarksBar.toggle()
    }

    /// Reads every field the session persists, so any change schedules a save.
    private func observeSessionState() {
        _ = tabs.selectedID
        for tab in tabs.tabs { _ = (tab.url, tab.title, tab.isPinned) }
        services.scheduleSessionSave()
    }

    var snapshot: WindowSnapshot {
        WindowSnapshot(frame: window?.frame, tabs: tabs.tabs.map(\.snapshot), selectedIndex: tabs.selectedIndex)
    }

    /// True when closing the window would lose nothing worth reopening.
    private var isDisposable: Bool {
        tabs.tabs.allSatisfy { $0.url == nil }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Tabs

    @discardableResult
    func openTab(url: URL?, select: Bool, opener: Tab? = nil) -> Tab {
        let tab = Tab(url: url, openerID: opener?.id)
        tab.delegate = self
        tabs.insert(tab, select: select)
        return tab
    }

    /// Opens `url` from outside the window: reuses an untouched blank tab, else a new tab.
    func open(_ url: URL) {
        if let tab = tabs.selected, tab.url == nil, !tab.canGoBack {
            tab.load(url)
            focusPage()
        } else {
            openTab(url: url, select: true)
        }
    }

    func close(_ tab: Tab) {
        if tabs.tabs.count > 1, tab.url != nil, let index = tabs.index(of: tab) {
            services.remember(.tab(tab.snapshot, index: index))
        }
        tab.stop()
        tab.webView?.removeFromSuperview()
        tabs.remove(tab)
        if tabs.tabs.isEmpty { window?.close() }
    }

    private var shownTabID: UUID?

    private func showSelectedTab() {
        guard let tab = tabs.selected else { return }
        window?.title = tab.displayTitle
        let webView = tab.materialize()
        guard shownTabID != tab.id else { return }
        shownTabID = tab.id
        rootView.show(webView)
        // Switching tabs abandons whatever was typed for the previous one.
        if rootView.toolbar.addressField.isEditing, tab.url != nil {
            focusPage()
        }
    }

    private func navigate(to text: String) {
        guard let url = AddressInput.resolve(text) else { return }
        let tab = tabs.selected ?? openTab(url: nil, select: true)
        tab.nextNavigationIsTyped = true
        tab.load(url)
        focusPage()
    }

    /// Reopens a closed tab where it was.
    func restore(_ snapshot: TabSnapshot, at index: Int) {
        let tab = Tab(snapshot: snapshot)
        tab.openerID = nil
        tab.delegate = self
        tabs.insert(tab, select: true)
        tabs.move(tab, to: index)
        services.applyCachedFavicon(to: tab)
    }

    private func focusAddressField() {
        DispatchQueue.main.async { [weak self] in self?.rootView.toolbar.addressField.focus() }
    }

    func focusPage() {
        if let webView = tabs.selected?.webView { window?.makeFirstResponder(webView) }
    }

    // MARK: Tab context menu

    private func contextMenu(for tab: Tab) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(closureMenuItem(tab.isPinned ? "Unpin Tab" : "Pin Tab") { [weak self] in
            self?.tabs.setPinned(tab, !tab.isPinned)
        })
        menu.addItem(closureMenuItem("Duplicate Tab") { [weak self] in self?.duplicate(tab) })
        menu.addItem(closureMenuItem("Reload Tab") { tab.reload() })
        if let url = tab.url {
            menu.addItem(.separator())
            menu.addItem(closureMenuItem("Copy Link") { Pasteboard.copy(url: url, title: tab.title) })
        }
        menu.addItem(.separator())
        menu.addItem(closureMenuItem("Close Tab") { [weak self] in self?.close(tab) })
        menu.addItem(closureMenuItem("Close Other Tabs") { [weak self] in
            self?.closeTabs(where: { $0 !== tab && !$0.isPinned })
        })
        if let index = tabs.index(of: tab) {
            menu.addItem(closureMenuItem("Close Tabs to the Right") { [weak self] in
                guard let self else { return }
                let right = Set(tabs.tabs.dropFirst(index + 1).map(\.id))
                closeTabs(where: { right.contains($0.id) })
            })
        }
        return menu
    }

    private func duplicate(_ tab: Tab) {
        var snapshot = tab.snapshot
        snapshot.id = UUID()
        snapshot.isPinned = false
        let copy = Tab(snapshot: snapshot)
        copy.openerID = tab.id
        copy.delegate = self
        tabs.insert(copy, select: true)
        services.applyCachedFavicon(to: copy)
    }

    private func closeTabs(where predicate: (Tab) -> Bool) {
        for tab in tabs.tabs where predicate(tab) { close(tab) }
    }

    // MARK: Menu actions

    @objc func copyURL(_ sender: Any?) {
        guard let tab = tabs.selected, let url = tab.url else { return }
        Pasteboard.copy(url: url, title: tab.title)
    }

    @objc func togglePinTab(_ sender: Any?) {
        if let tab = tabs.selected { tabs.setPinned(tab, !tab.isPinned) }
    }

    @objc func duplicateTab(_ sender: Any?) {
        if let tab = tabs.selected { duplicate(tab) }
    }

    /// ⌘T opens the command bar; picking a page opens it in a new tab.
    @objc func newTab(_ sender: Any?) {
        guard let window else { return }
        if commandBar.isVisible { return commandBar.hide() }
        services.commands = MenuCommands.collect()
        commandBar.show(over: window, chromeHeight: rootView.chromeHeight)
    }

    /// A blank tab, for when a page should start empty (also the strip's + button with ⌥).
    @objc func newBlankTab(_ sender: Any?) {
        openTab(url: nil, select: true)
        focusAddressField()
    }

    func activate(_ row: Suggestion, inNewTab: Bool) {
        switch row.action {
        case .open(let url):
            let typed = row.kind == .navigate || row.kind == .search || row.kind == .keyword
            if inNewTab, !(tabs.selected.map { $0.url == nil && !$0.canGoBack } ?? false) {
                let tab = openTab(url: nil, select: true)
                tab.nextNavigationIsTyped = typed
                tab.load(url)
            } else {
                let tab = tabs.selected ?? openTab(url: nil, select: true)
                tab.nextNavigationIsTyped = typed
                tab.load(url)
            }
            focusPage()
        case .switchToTab(let id):
            for controller in NSApp.orderedWindows.compactMap({ $0.windowController as? BrowserWindowController }) {
                guard let tab = controller.tabs.tabs.first(where: { $0.id == id }) else { continue }
                controller.tabs.select(tab)
                controller.window?.makeKeyAndOrderFront(nil)
                controller.focusPage()
                return
            }
        case .command(let selector):
            NSApp.sendAction(NSSelectorFromString(selector), to: nil, from: self)
        }
    }

    @objc func copyMarkdownLink(_ sender: Any?) {
        guard let tab = tabs.selected, let url = tab.url else { return }
        let title = tab.displayTitle.replacingOccurrences(of: "]", with: "\\]").replacingOccurrences(of: "[", with: "\\[")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("[\(title)](\(url.absoluteString))", forType: .string)
    }

    @objc func closeTab(_ sender: Any?) {
        if let tab = tabs.selected { close(tab) }
    }

    @objc func openLocation(_ sender: Any?) { focusAddressField() }
    @objc func goBack(_ sender: Any?) { tabs.selected?.goBack() }
    @objc func goForward(_ sender: Any?) { tabs.selected?.goForward() }
    @objc func reloadPage(_ sender: Any?) { tabs.selected?.reload() }
    @objc func hardReload(_ sender: Any?) { tabs.selected?.reload(fromOrigin: true) }
    @objc func stopLoading(_ sender: Any?) { tabs.selected?.stop() }

    @objc func reloadOrStop(_ sender: Any?) {
        guard let tab = tabs.selected else { return }
        if tab.isLoading { tab.stop() } else { tab.reload() }
    }

    @objc func zoomIn(_ sender: Any?) { adjustZoom { min($0 + 0.1, 3) } }
    @objc func zoomOut(_ sender: Any?) { adjustZoom { max($0 - 0.1, 0.3) } }
    @objc func actualSize(_ sender: Any?) { adjustZoom { _ in 1 } }

    private func adjustZoom(_ transform: (CGFloat) -> CGFloat) {
        guard let webView = tabs.selected?.webView else { return }
        webView.pageZoom = (transform(webView.pageZoom) * 10).rounded() / 10
    }

    @objc func selectNextTab(_ sender: Any?) { tabs.selectNext() }
    @objc func selectPreviousTab(_ sender: Any?) { tabs.selectPrevious() }

    /// ⌘1–⌘8 select by position; ⌘9 always selects the last tab.
    @objc func selectTabByNumber(_ sender: NSMenuItem) {
        if sender.tag == 9 { tabs.select(at: tabs.tabs.count - 1) } else { tabs.select(at: sender.tag - 1) }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(goBack(_:)): return tabs.selected?.canGoBack ?? false
        case #selector(goForward(_:)): return tabs.selected?.canGoForward ?? false
        case #selector(stopLoading(_:)): return tabs.selected?.isLoading ?? false
        case #selector(selectTabByNumber(_:)): return item.tag == 9 ? !tabs.tabs.isEmpty : item.tag <= tabs.tabs.count
        case #selector(toggleBookmarksBar(_:)):
            item.title = rootView.showsBookmarksBar ? "Hide Bookmarks Bar" : "Show Bookmarks Bar"
            return true
        case #selector(togglePinTab(_:)):
            item.title = tabs.selected?.isPinned == true ? "Unpin Tab" : "Pin Tab"
            return tabs.selected != nil
        case #selector(toggleBookmark(_:)):
            let bookmarked = tabs.selected?.url.flatMap { services.bookmarks.bookmark(for: $0) } != nil
            item.title = bookmarked ? "Remove Bookmark" : "Bookmark This Page"
            return tabs.selected?.url != nil
        default: return true
        }
    }

    // MARK: Window

    func windowWillEnterFullScreen(_ notification: Notification) { rootView.isFullScreen = true }
    func windowWillExitFullScreen(_ notification: Notification) { rootView.isFullScreen = false }

    func windowWillClose(_ notification: Notification) {
        if !isDisposable, tabs.tabs.count > 0 {
            if tabs.tabs.count == 1, let tab = tabs.tabs.first {
                services.remember(.tab(tab.snapshot, index: 0))
            } else {
                services.remember(.window(snapshot))
            }
        }
        for tab in tabs.tabs { tab.stop() }
        selectionObservation?.cancel()
        sessionObservation?.cancel()
        bookmarkObservation?.cancel()
        onClose?(self)
    }
}

extension BrowserWindowController: TabDelegate {
    func tab(_ tab: Tab, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction) -> WKWebView? {
        let webView = WebViewFactory.makeWebView(configuration: configuration)
        let child = Tab(adopting: webView, openerID: tab.id)
        child.delegate = self
        tabs.insert(child, select: !action.modifierFlags.contains(.command))
        return webView
    }

    func tab(_ tab: Tab, openInNewTab url: URL, inBackground: Bool) {
        openTab(url: url, select: !inBackground, opener: tab)
    }

    func tabDidRequestClose(_ tab: Tab) { close(tab) }

    func tabDidCommitNavigation(_ tab: Tab) {
        services.applyCachedFavicon(to: tab)
        guard let url = tab.url else { return }
        if let host = DisplayURL(url)?.host { services.suggestions.noteVisit(host: host) }
        let typed = tab.nextNavigationIsTyped
        let title = tab.title
        Task { try? await services.history.recordVisit(url: url, title: title, typed: typed) }
    }

    func tabDidFinishNavigation(_ tab: Tab) {
        services.refreshFavicon(for: tab)
        guard let url = tab.url else { return }
        let title = tab.title
        Task { try? await services.history.updateTitle(url: url, title: title) }
    }
}

/// Lets the window claim key-equivalents before the web view swallows them.
final class BrowserWindow: NSWindow {}

/// Stacks strip, toolbar, and page. Frame-based so window resizes cost one layout pass.
final class BrowserRootView: NSView {
    let strip: TabStripView
    let toolbar: ToolbarView
    let bookmarksBar = BookmarksBarView(library: AppServices.shared.bookmarks)

    var showsBookmarksBar = UserDefaults.standard.object(forKey: "ShowBookmarksBar") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showsBookmarksBar, forKey: "ShowBookmarksBar")
            bookmarksBar.isHidden = !showsBookmarksBar
            toolbar.showsHairline = !showsBookmarksBar
            needsLayout = true
        }
    }
    private let content = NSView()
    private weak var current: WKWebView?

    var isFullScreen = false { didSet { strip.leadingInset = isFullScreen ? 12 : Theme.trafficLightInset } }

    init(tabs: TabCollection) {
        strip = TabStripView(tabs: tabs)
        toolbar = ToolbarView(tabs: tabs)
        super.init(frame: .zero)
        content.wantsLayer = true
        [content, strip, toolbar, bookmarksBar].forEach(addSubview)
        bookmarksBar.isHidden = !showsBookmarksBar
        toolbar.showsHairline = !showsBookmarksBar
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        let height = bounds.height
        strip.frame = NSRect(x: 0, y: height - Theme.stripHeight, width: bounds.width, height: Theme.stripHeight)
        toolbar.frame = NSRect(x: 0, y: strip.frame.minY - Theme.toolbarHeight, width: bounds.width, height: Theme.toolbarHeight)
        var contentTop = toolbar.frame.minY
        if showsBookmarksBar {
            bookmarksBar.frame = NSRect(x: 0, y: contentTop - BookmarksBarView.height, width: bounds.width, height: BookmarksBarView.height)
            contentTop = bookmarksBar.frame.minY
        }
        content.frame = NSRect(x: 0, y: 0, width: bounds.width, height: contentTop)
        current?.frame = content.bounds
    }

    /// Height of everything above the page.
    var chromeHeight: CGFloat { bounds.height - content.frame.maxY }

    func show(_ webView: WKWebView) {
        guard current !== webView else { return }
        current?.removeFromSuperview()
        webView.frame = content.bounds
        webView.autoresizingMask = [.width, .height]
        content.addSubview(webView)
        current = webView
    }
}
