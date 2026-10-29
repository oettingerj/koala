import AppKit
import Observation
import os
import WebKit

/// Window-level UI a page can ask for: JavaScript dialogs, permission prompts, file pickers,
/// and downloads. Implemented by the window that shows the tab.
@MainActor
public protocol TabUIHost: AnyObject {
    func tab(_ tab: Tab, alert message: String, from origin: String) async
    func tab(_ tab: Tab, confirm message: String, from origin: String) async -> Bool
    func tab(_ tab: Tab, prompt message: String, defaultText: String?, from origin: String) async -> String?
    func tab(_ tab: Tab, chooseFiles parameters: WKOpenPanelParameters) async -> [URL]?
    func tab(_ tab: Tab, allowMediaCapture type: WKMediaCaptureType, from origin: String) async -> Bool
    /// A server asked for HTTP authentication. `failures` counts rejected attempts so far. Return nil to cancel.
    func tab(_ tab: Tab, credentialFor space: URLProtectionSpace, failures: Int) async -> URLCredential?
    func tab(_ tab: Tab, didStart download: WKDownload)
    /// The PDF viewer's download button handed over the document's bytes to save.
    func tab(_ tab: Tab, save data: Data, suggestedFilename: String, from source: URL?)
}

@MainActor
public protocol TabDelegate: AnyObject {
    /// A page asked for a new window (`target=_blank`, `window.open`). Return the web view
    /// that should host it, built from `configuration`, or nil to refuse.
    func tab(_ tab: Tab, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction) -> WKWebView?
    /// A link was ⌘-clicked or middle-clicked.
    func tab(_ tab: Tab, openInNewTab url: URL, inBackground: Bool)
    /// A link was ⇧-clicked: preview it without leaving the page.
    func tab(_ tab: Tab, peek url: URL)
    func tabDidRequestClose(_ tab: Tab)
    /// The page's web content process quit (a crash, or killed for memory). The tab shows nothing until
    /// it reloads: the window calls `recoverFromCrash()` if the tab is in view, else `sleep()`.
    func tabWebContentProcessDidTerminate(_ tab: Tab)
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
    /// The second page when this tab is a split view. It is not in the strip on its own.
    public var splitTab: Tab?

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
    @ObservationIgnored public weak var uiHost: TabUIHost?
    /// Observed so the window re-shows the tab when moving between the web and extension pages swaps it.
    public private(set) var webView: WKWebView?
    /// The extension whose configuration the web view was cut from (nil for the web), or unknown
    /// for a web view WebKit created for a popup.
    @ObservationIgnored private var webViewExtension: String?? = .some(nil)
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var errorNavigation: WKNavigation?
    /// The server behind a certificate error page, which its "Visit Anyway" link may accept.
    @ObservationIgnored private var pendingTrustKey: String?
    /// Polls a local server that refused the connection, and reloads when it answers.
    @ObservationIgnored private var serverWait: Task<Void, Never>?
    @ObservationIgnored private var lastCrash: Date?
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
        super.init()
        if let page { showNative(page) }
    }

    public convenience init(snapshot: TabSnapshot) {
        self.init(id: snapshot.id, url: snapshot.url, title: snapshot.title, openerID: snapshot.openerID)
        isPinned = snapshot.isPinned
        restoredState = snapshot.interactionState
        if let split = snapshot.split {
            let partner = Tab(url: split.url, title: split.title)
            partner.restoredState = split.interactionState
            splitTab = partner
        }
    }

    /// Everything needed to bring this tab back after quit or close, without loading it now.
    public var snapshot: TabSnapshot {
        var snapshot = TabSnapshot(id: id, url: url, title: title, isPinned: isPinned, openerID: openerID,
                                   interactionState: currentInteractionState)
        if let splitTab {
            snapshot.split = SplitSnapshot(url: splitTab.url, title: splitTab.title, interactionState: splitTab.currentInteractionState)
        }
        return snapshot
    }

    private var currentInteractionState: Data? {
        (webView?.interactionState as? Data) ?? restoredState
    }

    /// Native pages keep their own icon.
    public func setFavicon(_ image: NSImage?) {
        guard page == nil else { return }
        favicon = image
    }

    /// The native page this tab shows instead of a web view, if any.
    public var page: KoalaPage? { KoalaPage(url: url) }

    /// When the tab was last shown; background tabs idle long enough are put to sleep.
    @ObservationIgnored public private(set) var lastActiveAt = Date()
    public func markActive() { lastActiveAt = Date() }

    /// Releases the web view and its WebContent process memory, keeping back/forward state.
    /// The next `materialize()` restores the page.
    public func sleep() {
        guard let webView else { return }
        restoredState = (webView.interactionState as? Data) ?? restoredState
        detachWebView()
    }

    /// True when a text field holds something the user typed: putting the tab to sleep would lose it.
    public func hasUnsavedInput() async -> Bool {
        guard let webView else { return false }
        let result = try? await webView.callAsyncJavaScript(Self.unsavedInputCheck, contentWorld: DevToolsScripts.world)
        return result as? Bool ?? false
    }

    private static let unsavedInputCheck = """
        if (document.activeElement?.isContentEditable) return true;
        const text = new Set(['text', 'search', 'email', 'url', 'tel', 'number']);
        for (const input of document.querySelectorAll('input')) {
          if (text.has(input.type) && input.value !== input.defaultValue) return true;
        }
        for (const area of document.querySelectorAll('textarea')) {
          if (area.value !== area.defaultValue) return true;
        }
        return false;
        """

    /// Reloads a page whose web content process quit. A second crash within 10 seconds shows an
    /// error page instead, so a page that crashes on load doesn't loop.
    public func recoverFromCrash() {
        guard let webView else { return }
        let now = Date()
        if let lastCrash, now.timeIntervalSince(lastCrash) < 10, let url {
            errorNavigation = webView.loadHTMLString(ErrorPage.crashed(url), baseURL: url)
        } else {
            webView.reload()
        }
        lastCrash = now
    }

    private func detachWebView() {
        guard let webView else { return }
        webView.stopLoading()
        webView.removeFromSuperview()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        observations = []
        self.webView = nil
        automaticPictureInPicture = nil
        serverWait?.cancel()
        serverWait = nil
        isLoading = false
        progress = 0
    }

    /// Picture in Picture this tab started on its own as it left view; nil when none.
    @ObservationIgnored private var automaticPictureInPicture: Task<Bool, Never>?

    /// Picks the largest playing, audible video. Muted previews and background loops stay put.
    private static let enterPictureInPicture = """
        if (!document.pictureInPictureEnabled || document.pictureInPictureElement) return false;
        const video = [...document.querySelectorAll('video')]
          .filter(v => !v.paused && !v.ended && !v.muted && v.volume > 0 && v.readyState >= 2 && !v.disablePictureInPicture)
          .sort((a, b) => b.clientWidth * b.clientHeight - a.clientWidth * a.clientHeight)[0];
        if (!video) return false;
        await video.requestPictureInPicture();
        return true;
        """

    /// Moves a playing video into Picture in Picture as the tab leaves view. Script calls from the
    /// app count as a user gesture, which `requestPictureInPicture` needs.
    public func enterPictureInPictureIfPlaying() {
        guard let webView, automaticPictureInPicture == nil else { return }
        automaticPictureInPicture = Task {
            (try? await webView.callAsyncJavaScript(Self.enterPictureInPicture, contentWorld: DevToolsScripts.world)) as? Bool ?? false
        }
    }

    /// Brings back inline a video `enterPictureInPictureIfPlaying` moved out; leaves PiP the user started.
    public func exitAutomaticPictureInPicture() {
        guard let webView, let entering = automaticPictureInPicture else { return }
        automaticPictureInPicture = nil
        Task {
            guard await entering.value else { return }
            _ = try? await webView.callAsyncJavaScript("if (document.pictureInPictureElement) await document.exitPictureInPicture();",
                                                       contentWorld: DevToolsScripts.world)
        }
    }

    /// Wraps a web view WebKit already created for a popup.
    public init(adopting webView: WKWebView, openerID: UUID?) {
        self.id = UUID()
        self.url = nil
        self.title = ""
        self.openerID = openerID
        super.init()
        attach(webView)
        webViewExtension = nil
        // KVO reports changes only; a web view adopted mid-load (Peek) already has state.
        url = webView.url
        title = webView.title ?? ""
        isLoading = webView.isLoading
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
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
        let webView = WebViewFactory.makeWebView(for: url)
        attach(webView)
        webViewExtension = .some(WebViewFactory.extensionHost(of: url))
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
        if let page = KoalaPage(url: url) {
            // Native pages have no web view; back/forward history goes with the old one.
            restoredState = nil
            detachWebView()
            showNative(page)
        } else if let webView, !needsNewWebView(for: url) {
            webView.load(URLRequest(url: url))
        } else {
            // Moving between the web and an extension's pages needs a web view with the other
            // configuration; back/forward history stays with the old one.
            restoredState = nil
            detachWebView()
            materialize()
        }
    }

    private func showNative(_ page: KoalaPage) {
        title = page.title
        favicon = page.icon
        canGoBack = false
        canGoForward = false
        isJSONDocument = false
        isShowingErrorPage = false
        webViewExtension = .some(nil)
    }

    private func needsNewWebView(for url: URL) -> Bool {
        guard case .some(let current) = webViewExtension else { return false }
        return WebViewFactory.extensionHost(of: url) != current
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
        guard page == nil else { return }
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
        // Only the app opens native pages; a web page linking to one must not reach them.
        if action.request.url?.scheme?.lowercased() == KoalaPage.scheme {
            if action.request.url == ErrorPage.proceedURL { acceptCertificate(for: action) }
            return (.cancel, preferences)
        }
        if action.targetFrame?.isMainFrame == true, let url = action.request.url, needsNewWebView(for: url) {
            load(url)
            return (.cancel, preferences)
        }
        let flags = action.modifierFlags.intersection([.command, .shift, .option, .control])
        if action.navigationType == .linkActivated, flags == .shift, let url = action.request.url,
           url.scheme == "http" || url.scheme == "https" {
            delegate?.tab(self, peek: url)
            return (.cancel, preferences)
        }
        let opensNewTab = action.navigationType == .linkActivated
            && (action.modifierFlags.contains(.command) || action.buttonNumber == 2)
        if opensNewTab, let url = action.request.url {
            delegate?.tab(self, openInNewTab: url, inBackground: !action.modifierFlags.contains(.shift))
            return (.cancel, preferences)
        }
        preferences.allowsContentJavaScript = javaScriptEnabled
        if action.shouldPerformDownload { return (.download, preferences) }
        return (.allow, preferences)
    }

    public func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        uiHost?.tab(self, didStart: download)
    }

    public func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        uiHost?.tab(self, didStart: download)
    }

    public func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        if response.isForMainFrame {
            devTools.record(response: response.response)
            let mime = response.response.mimeType ?? ""
            isJSONDocument = mime == "application/json" || mime.hasSuffix("+json")
        }
        // Attachments and types WebKit cannot render are downloads.
        let http = response.response as? HTTPURLResponse
        let disposition = http?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        if disposition.lowercased().hasPrefix("attachment") || !response.canShowMIMEType {
            Logger(subsystem: "com.joshoettinger.koala", category: "navigation").info("""
                download mainFrame=\(response.isForMainFrame) status=\(http?.statusCode ?? -1) \
                mime=\(response.response.mimeType ?? "nil", privacy: .public) canShow=\(response.canShowMIMEType) \
                disposition=\(disposition, privacy: .public) url=\(response.response.url?.absoluteString ?? "", privacy: .public)
                """)
            return .download
        }
        return .allow
    }

    /// "Visit Anyway" on this tab's own certificate error page. The server comes from the tab's state,
    /// never from the link, so no other page can accept a certificate.
    private func acceptCertificate(for action: WKNavigationAction) {
        guard isShowingErrorPage, action.navigationType == .linkActivated, action.sourceFrame.isMainFrame,
              let key = pendingTrustKey, let url, let webView else { return }
        pendingTrustKey = nil
        TrustExceptions.shared.insert(key)
        webView.load(URLRequest(url: url))
    }

    public func webView(_ webView: WKWebView, respondTo challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        switch space.authenticationMethod {
        case NSURLAuthenticationMethodServerTrust:
            guard let trust = space.serverTrust, TrustExceptions.shared.contains(host: space.host, port: space.port)
            else { return (.performDefaultHandling, nil) }
            return (.useCredential, URLCredential(trust: trust))
        case NSURLAuthenticationMethodHTTPBasic, NSURLAuthenticationMethodHTTPDigest, NSURLAuthenticationMethodNTLM:
            guard challenge.previousFailureCount < 3,
                  let credential = await uiHost?.tab(self, credentialFor: space, failures: challenge.previousFailureCount)
            else { return (.cancelAuthenticationChallenge, nil) }
            return (.useCredential, credential)
        default:
            return (.performDefaultHandling, nil)
        }
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoading = false
        progress = 0
        delegate?.tabWebContentProcessDidTerminate(self)
    }

    public func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        isShowingErrorPage = navigation != nil && navigation === errorNavigation
        if !isShowingErrorPage { pendingTrustKey = nil }
        devTools.reset()
        if isShowingErrorPage { devTools.endCapture() }
        bindDevToolsDocument(webView)
        if !isShowingErrorPage {
            delegate?.tabDidCommitNavigation(self)
        }
        nextNavigationIsTyped = false
    }

    private func bindDevToolsDocument(_ webView: WKWebView) {
        let generation = devTools.navigationID
        Task { [weak self, weak webView] in
            guard let webView,
                  let page = try? await webView.evaluateJavaScript("globalThis.__koalaDocumentID", contentWorld: .page) as? String,
                  let isolated = try? await webView.evaluateJavaScript("globalThis.__koalaDocumentID", contentWorld: DevToolsScripts.world) as? String,
                  let self, self.devTools.navigationID == generation else { return }
            self.devTools.bindDocument(page, isolated: isolated)
        }
    }

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if !isShowingErrorPage { delegate?.tabDidFinishNavigation(self) }
    }

    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        devTools.willNavigate()
        if navigation !== errorNavigation {
            serverWait?.cancel()
            serverWait = nil
        }
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard !ErrorPage.isSilent(error) else { bindDevToolsDocument(webView); return }
        let failingURL = (error as NSError).userInfo[NSURLErrorFailingURLErrorKey] as? URL ?? url
        guard let failingURL else { return }
        // Base URL keeps the address field on the URL that failed; "Try Again" links back to it.
        errorNavigation = webView.loadHTMLString(ErrorPage.html(for: failingURL, error: error), baseURL: failingURL)
        pendingTrustKey = ErrorPage.isCertificateError(error) ? TrustExceptions.key(for: failingURL) : nil
        if ErrorPage.waitsForServer(failingURL, error: error) { waitForServer(at: failingURL) }
    }

    private static let probeSession = URLSession(configuration: .ephemeral)

    /// Probes the server until anything answers, then loads the page. A response of any kind, or
    /// any error other than a refused connection, means something is listening.
    private func waitForServer(at url: URL) {
        serverWait?.cancel()
        serverWait = Task { [weak self] in
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 1)
            request.httpMethod = "HEAD"
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { return }
                do {
                    _ = try await Self.probeSession.data(for: request)
                } catch let error as URLError where error.code == .cannotConnectToHost {
                    continue
                } catch {}
                guard let self, !Task.isCancelled, self.isShowingErrorPage, self.url == url else { return }
                self.serverWait = nil
                self.webView?.load(URLRequest(url: url))
                return
            }
        }
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

    private func origin(_ frame: WKFrameInfo) -> String {
        let origin = frame.securityOrigin
        return origin.port == 0 ? origin.host : "\(origin.host):\(origin.port)"
    }

    public func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                        initiatedByFrame frame: WKFrameInfo) async {
        await uiHost?.tab(self, alert: message, from: origin(frame))
    }

    public func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                        initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await uiHost?.tab(self, confirm: message, from: origin(frame)) ?? false
    }

    public func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                        defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        await uiHost?.tab(self, prompt: prompt, defaultText: defaultText, from: origin(frame))
    }

    public func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                        initiatedByFrame frame: WKFrameInfo) async -> [URL]? {
        await uiHost?.tab(self, chooseFiles: parameters)
    }

    public func webView(_ webView: WKWebView, decideMediaCapturePermissionsFor origin: WKSecurityOrigin,
                        initiatedBy frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        let name = origin.port == 0 ? origin.host : "\(origin.host):\(origin.port)"
        return await uiHost?.tab(self, allowMediaCapture: type, from: name) == true ? .grant : .deny
    }

    /// WebKit SPI: the window frame behind `window.outerWidth`, `outerHeight`, `screenX` and `screenY`.
    /// Without it they are all 0, and pages that read zoom from `outerWidth / innerWidth` (Google
    /// Docs) think the page is zoomed out and draw their canvas at a fraction of its resolution.
    @objc(_webView:getWindowFrameWithCompletionHandler:)
    public func webViewGetWindowFrame(_ webView: WKWebView, completionHandler: @escaping (CGRect) -> Void) {
        completionHandler(webView.window?.frame ?? .zero)
    }

    /// WebKit SPI: the built-in PDF viewer's download button. Without it the button does nothing.
    @objc(_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:)
    public func webViewSaveData(_ webView: WKWebView, data: Data, suggestedFilename: String,
                                mimeType: String?, originatingURL: URL?) {
        uiHost?.tab(self, save: data, suggestedFilename: suggestedFilename, from: originatingURL)
    }
}
