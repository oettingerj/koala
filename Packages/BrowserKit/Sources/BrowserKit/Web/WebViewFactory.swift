import WebKit

/// Owns the configuration every tab's web view is cut from, and makes private windows' configurations.
@MainActor
public enum WebViewFactory {
    public static let configuration: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()
        configure(config, store: .default())
        return config
    }()

    /// A configuration for private windows: its own in-memory data store, so nothing stored in it
    /// outlives the configuration or reaches regular windows. No extensions run in it.
    public static func makePrivateConfiguration() -> WKWebViewConfiguration {
        let config = WKWebViewConfiguration()
        configure(config, store: .nonPersistent())
        return config
    }

    private static func configure(_ config: WKWebViewConfiguration, store: WKWebsiteDataStore) {
        config.websiteDataStore = store
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.isTextInteractionEnabled = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        // macOS WKWebView has Picture in Picture off, and only this private setter turns it on.
        // Without it PiP requests fail and nothing else changes.
        let allowPictureInPicture = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")
        if config.preferences.responds(to: allowPictureInPicture) {
            config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        }
        config.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        DevToolsScripts.install(on: config.userContentController, handler: DevToolsRouter.shared)
        KoalaWebView.installPageTracking(on: config.userContentController)
        config.userContentController.addUserScript(WKUserScript(source: scrollbarStyle, injectionTime: .atDocumentStart,
                                                                forMainFrameOnly: false, in: .defaultClient))
    }

    /// Light, thin scrollbars that darken on hover. In a cascade layer so any scrollbar styles the
    /// page sets win; a constructed stylesheet because strict CSP blocks `<style>` elements.
    static let scrollbarStyle = """
    (() => {
      const sheet = new CSSStyleSheet();
      sheet.replaceSync(`@layer koala-default {
        ::-webkit-scrollbar { width: 10px; height: 10px; background: transparent; }
        ::-webkit-scrollbar-thumb { background: rgb(128 128 128 / 0.3); background-clip: padding-box;
          border: 2px solid transparent; border-radius: 5px; }
        ::-webkit-scrollbar-thumb:hover { background-color: rgb(128 128 128 / 0.55); }
        ::-webkit-scrollbar-thumb:active { background-color: rgb(128 128 128 / 0.7); }
        ::-webkit-scrollbar-track, ::-webkit-scrollbar-corner { background: transparent; }
      }`);
      document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
    })();
    """

    /// The configuration a web extension's own pages need, for URLs inside that extension. Set by the app.
    public static var extensionConfiguration: ((URL) -> WKWebViewConfiguration?)?

    /// The extension a URL belongs to (the host of its `webkit-extension:` URL), or nil for the web.
    /// WebKit only loads an extension's pages in web views cut from that extension's configuration.
    public static func extensionHost(of url: URL?) -> String? {
        guard let url, url.scheme == "webkit-extension" else { return nil }
        return url.host()
    }

    /// A web view that can show `url`: extension pages get their extension's configuration, other
    /// pages `base` (a private window's), or the shared configuration.
    public static func makeWebView(for url: URL?, base: WKWebViewConfiguration? = nil) -> WKWebView {
        makeWebView(configuration: url.flatMap { extensionConfiguration?($0) } ?? base)
    }

    /// `configuration` must be the one WebKit hands to `createWebViewWith` when opening a popup;
    /// otherwise the shared configuration is used.
    public static func makeWebView(configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        let webView = KoalaWebView(frame: .zero, configuration: configuration ?? self.configuration)
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        return webView
    }
}
