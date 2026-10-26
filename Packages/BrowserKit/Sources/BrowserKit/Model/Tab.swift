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

    @ObservationIgnored public weak var delegate: TabDelegate?
    @ObservationIgnored public private(set) var webView: WKWebView?
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var errorNavigation: WKNavigation?
    public private(set) var isShowingErrorPage = false

    public init(id: UUID = UUID(), url: URL?, title: String = "", openerID: UUID? = nil) {
        self.id = id
        self.url = url
        self.title = title
        self.openerID = openerID
    }

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
        if let url { webView.load(URLRequest(url: url)) }
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
        return (.allow, preferences)
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        favicon = nil
        isShowingErrorPage = navigation != nil && navigation === errorNavigation
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
