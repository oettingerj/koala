import AppKit
import Observation
import WebKit

@MainActor
public protocol TabDelegate: AnyObject {
    /// A page asked for a new window (`target=_blank`, `window.open`). Return the web view
    /// that should host it, built from `configuration`, or nil to refuse.
    func tab(_ tab: Tab, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction) -> WKWebView?
    /// A link was ⌘-clicked or middle-clicked.
    func tab(_ tab: Tab, openInNewTab url: URL, inBackground: Bool)
    func tabDidRequestClose(_ tab: Tab)
    /// A main-frame navigation committed (the URL changed for real) or finished loading.
    func tabDidCommitNavigation(_ tab: Tab)
    func tabDidFinishNavigation(_ tab: Tab)
}

/// One page in a window. The web view is created lazily, so restored or background tabs
/// cost nothing until they are shown.
@MainActor
@Observable
public final class Tab: NSObject, Identifiable {
    public let id: UUID
    public internal(set) var url: URL?
    public internal(set) var title: String
    public internal(set) var isLoading = false
    public internal(set) var progress: Double = 0
    public internal(set) var canGoBack = false
    public internal(set) var canGoForward = false
    public internal(set) var favicon: NSImage?
    public var openerID: UUID?
    public var isPinned = false

    /// Console, network timing, vitals, and the main response for the dev panel.
    @ObservationIgnored public let devTools = DevToolsRecord()
    /// Page tools. Changing JavaScript takes effect on the next load.
    public var javaScriptEnabled = true
    /// Responsive mode: the page is laid out at this width, centered. nil fills the window.
    public var viewportWidth: CGFloat?
    /// Forces `prefers-color-scheme` for this tab: "light", "dark", or nil to follow the system.
    public var colorSchemeOverride: String?
    /// The main document was served as JSON; the app shows its viewer once loaded.
    public private(set) var isJSONDocument = false

    @ObservationIgnored public weak var delegate: TabDelegate?
    @ObservationIgnored public private(set) var webView: WKWebView?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var errorNavigation: WKNavigation?
    /// Back/forward state from a restored session, applied when the web view is created.
    @ObservationIgnored private var restoredState: Data?
    /// The next committed navigation came from the address field (counts as typed in history).
    @ObservationIgnored public var nextNavigationIsTyped = false
    public private(set) var isShowingErrorPage = false

    public init(id: UUID = UUID(), url: URL?, title: String = "", openerID: UUID? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.openerID = openerID
    }

    public convenience init(snapshot: TabSnapshot) {
        self.init(id: snapshot.id, url: snapshot.url, title: snapshot.title, openerID: snapshot.openerID)
        isPinned = snapshot.isPinned
        restoredState = snapshot.interactionState
    }

    /// Everything needed to bring this tab back after quit or close, without loading it now.
    public var snapshot: TabSnapshot {
        TabSnapshot(id: id, url: url, title: title, isPinned: isPinned, openerID: openerID,
                    interactionState: (webView?.interactionState as? Data) ?? restoredState)
    }

    public func setFavicon(_ image: NSImage?) { favicon = image }

    /// Wraps a web view WebKit already created for a popup.
    public init(adopting webView: WKWebView, openerID: UUID?) {
        self.id = UUID()
        self.url = nil
        self.title = ""
        self.openerID = openerID
        super.init()
        attach(webView)
    }

    public var displayTitle: String {
        if !title.isEmpty { return title }
        if let host = url?.host(percentEncoded: false) { return host }
        return "New Tab"
    }

    /// Creates the web view on first use and loads the tab's URL.
    @discardableResult
    public func materialize() -> WKWebView {
        if let webView { return webView }
        let webView = WebViewFactory.makeWebView()
        attach(webView)
        if let restoredState {
            webView.interactionState = restoredState
            self.restoredState = nil
        } else if let url {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    public func load(_ url: URL) {
        self.url = url
        if let webView {
            webView.load(URLRequest(url: url))
        } else {
            materialize()
        }
    }

    /// Shows generated HTML (view source, tool pages) under `baseURL`.
    public func loadHTML(_ html: String, baseURL: URL?, title: String) {
        let webView = materialize()
        self.title = title
        webView.loadHTMLString(html, baseURL: baseURL)
    }

    public func goBack() { webView?.goBack() }
    public func goForward() { webView?.goForward() }
    public func stop() { webView?.stopLoading() }

    public func reload(fromOrigin: Bool = false) {
        guard let webView else {
            materialize()
            return
        }
        // The error page was loaded from a string; reloading it would only redraw the error.
        if isShowingErrorPage, let url {
            webView.load(URLRequest(url: url))
        } else if fromOrigin {
            webView.reloadFromOrigin()
        } else {
            webView.reload()
        }
    }

    private func attach(_ webView: WKWebView) {
        self.webView = webView
        DevToolsRouter.shared.register(devTools, for: webView)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        observations = [
            webView.observe(\.title) { [weak self] wv, _ in MainActor.assumeIsolated { self?.title = wv.title ?? "" } },
            webView.observe(\.url) { [weak self] wv, _ in MainActor.assumeIsolated { if let url = wv.url { self?.url = url } } },
            webView.observe(\.isLoading) { [weak self] wv, _ in MainActor.assumeIsolated { self?.isLoading = wv.isLoading } },
            webView.observe(\.estimatedProgress) { [weak self] wv, _ in MainActor.assumeIsolated { self?.progress = wv.estimatedProgress } },
            webView.observe(\.canGoBack) { [weak self] wv, _ in MainActor.assumeIsolated { self?.canGoBack = wv.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] wv, _ in MainActor.assumeIsolated { self?.canGoForward = wv.canGoForward } },
        ]
    }
}

extension Tab: WKNavigationDelegate {
    public func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                        preferences: WKWebpagePreferences) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        let opensNewTab = action.navigationType == .linkActivated
            && (action.modifierFlags.contains(.command) || action.buttonNumber == 2)
        if opensNewTab, let url = action.request.url {
            delegate?.tab(self, openInNewTab: url, inBackground: !action.modifierFlags.contains(.shift))
            return (.cancel, preferences)
        }
        preferences.allowsContentJavaScript = javaScriptEnabled
        return (.allow, preferences)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if response.isForMainFrame {
            devTools.record(response: response.response)
            let mime = response.response.mimeType ?? ""
            isJSONDocument = mime == "application/json" || mime.hasSuffix("+json")
        }
        return .allow
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        isShowingErrorPage = navigation != nil && navigation === errorNavigation
        devTools.reset()
        if !isShowingErrorPage {
            delegate?.tabDidCommitNavigation(self)
        }
        nextNavigationIsTyped = false
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !isShowingErrorPage { delegate?.tabDidFinishNavigation(self) }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !ErrorPage.isSilent(error) else { return }
        let failingURL = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? url
        guard let failingURL else { return }
        // Base URL keeps the address field on the URL that failed; "Try Again" links back to it.
        errorNavigation = webView.loadHTMLString(ErrorPage.html(for: failingURL, error: error), baseURL: failingURL)
    }
}

extension Tab: WKUIDelegate {
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        delegate?.tab(self, createWebViewWith: configuration, for: navigationAction)
    }

    public func webViewDidClose(_ webView: WKWebView) {
        delegate?.tabDidRequestClose(self)
    }
}
