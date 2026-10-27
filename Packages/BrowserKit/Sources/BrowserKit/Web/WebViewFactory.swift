import WebKit

/// Owns the one configuration every tab's web view is cut from.
@MainActor
public enum WebViewFactory {
    public static let configuration: WKWebViewConfiguration = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.preferences.isElementFullscreenEnabled = true
        config.preferences.isTextInteractionEnabled = true
        config.allowsAirPlayForMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = .all
        config.applicationNameForUserAgent = "Version/26.0 Safari/605.1.15"
        DevToolsScripts.install(on: config.userContentController, handler: DevToolsRouter.shared)
        return config
    }()

    /// `configuration` must be the one WebKit hands to `createWebViewWith` when opening a popup;
    /// otherwise the shared configuration is used.
    public static func makeWebView(configuration: WKWebViewConfiguration? = nil) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: configuration ?? self.configuration)
        webView.allowsMagnification = true
        webView.allowsBackForwardNavigationGestures = true
        webView.isInspectable = true
        return webView
    }
}
