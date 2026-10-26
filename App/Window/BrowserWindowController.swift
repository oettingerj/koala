import AppKit
import BrowserKit
import WebKit

/// One browser window: tab strip in the titlebar, toolbar, and the selected tab's page.
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let tabs = TabCollection()
    private let rootView: BrowserRootView
    private var selectionObservation: ObservationLoop?
    var onClose: ((BrowserWindowController) -> Void)?

    init(initialURL: URL? = nil) {
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
        super.init(window: window)
        window.delegate = self
        window.setFrameAutosaveName("NanoBrowserWindow")

        rootView.strip.onSelect = { [weak self] tab in self?.tabs.select(tab) }
        rootView.strip.onClose = { [weak self] tab in self?.close(tab) }
        rootView.toolbar.addressField.onSubmit = { [weak self] text in self?.navigate(to: text) }
        rootView.toolbar.addressField.onCancel = { [weak self] in self?.focusPage() }

        selectionObservation = ObservationLoop { [weak self] in self?.showSelectedTab() }

        openTab(url: initialURL, select: true)
        if initialURL == nil { focusAddressField() }
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
        if let tab = tabs.selected {
            tab.load(url)
        } else {
            openTab(url: url, select: true)
        }
        focusPage()
    }

    private func focusAddressField() {
        DispatchQueue.main.async { [weak self] in self?.rootView.toolbar.addressField.focus() }
    }

    private func focusPage() {
        if let webView = tabs.selected?.webView { window?.makeFirstResponder(webView) }
    }

    // MARK: Menu actions

    @objc func newTab(_ sender: Any?) {
        openTab(url: nil, select: true)
        focusAddressField()
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
        case #selector(goBack(_:)): tabs.selected?.canGoBack ?? false
        case #selector(goForward(_:)): tabs.selected?.canGoForward ?? false
        case #selector(stopLoading(_:)): tabs.selected?.isLoading ?? false
        case #selector(selectTabByNumber(_:)): item.tag == 9 ? !tabs.tabs.isEmpty : item.tag <= tabs.tabs.count
        default: true
        }
    }

    // MARK: Window

    func windowWillEnterFullScreen(_ notification: Notification) { rootView.isFullScreen = true }
    func windowWillExitFullScreen(_ notification: Notification) { rootView.isFullScreen = false }

    func windowWillClose(_ notification: Notification) {
        for tab in tabs.tabs { tab.stop() }
        selectionObservation?.cancel()
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
}

/// Lets the window claim key-equivalents before the web view swallows them.
final class BrowserWindow: NSWindow {}

/// Stacks strip, toolbar, and page. Frame-based so window resizes cost one layout pass.
final class BrowserRootView: NSView {
    let strip: TabStripView
    let toolbar: ToolbarView
    private let content = NSView()
    private weak var current: WKWebView?

    var isFullScreen = false { didSet { strip.leadingInset = isFullScreen ? 12 : Theme.trafficLightInset } }

    init(tabs: TabCollection) {
        strip = TabStripView(tabs: tabs)
        toolbar = ToolbarView(tabs: tabs)
        super.init(frame: .zero)
        content.wantsLayer = true
        [content, strip, toolbar].forEach(addSubview)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    override func layout() {
        super.layout()
        let height = bounds.height
        strip.frame = NSRect(x: 0, y: height - Theme.stripHeight, width: bounds.width, height: Theme.stripHeight)
        toolbar.frame = NSRect(x: 0, y: strip.frame.minY - Theme.toolbarHeight, width: bounds.width, height: Theme.toolbarHeight)
        content.frame = NSRect(x: 0, y: 0, width: bounds.width, height: toolbar.frame.minY)
        current?.frame = content.bounds
    }

    func show(_ webView: WKWebView) {
        guard current !== webView else { return }
        current?.removeFromSuperview()
        webView.frame = content.bounds
        webView.autoresizingMask = [.width, .height]
        content.addSubview(webView)
        current = webView
    }
}
