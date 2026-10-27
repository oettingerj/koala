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
        // macOS WKWebView has Picture in Picture off, and only this private setter turns it on.
        // The one WebKit SPI Nano uses; without it PiP requests fail and nothing else changes.
        let allowPictureInPicture = NSSelectorFromString("_setAllowsPictureInPictureMediaPlayback:")
        if config.preferences.responds(to: allowPictureInPicture) {
            config.preferences.setValue(true, forKey: "allowsPictureInPictureMediaPlayback")
        }
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
