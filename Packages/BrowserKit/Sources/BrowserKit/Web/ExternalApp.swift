import AppKit
import WebKit

/// Links WebKit can't load but another app on the Mac can: `zoommtg:`, `slack:`, `mailto:`, and the like.
@MainActor
public enum ExternalApp {
    /// The app that opens `url`, or nil when the web view should load it (or nothing can).
    public static func handler(for url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), !loadsInBrowser(scheme) else { return nil }
        return NSWorkspace.shared.urlForApplication(toOpen: url)
    }

    /// The app's name as Finder shows it, without ".app".
    public static func displayName(of app: URL) -> String {
        FileManager.default.displayName(atPath: app.path).replacingOccurrences(of: ".app", with: "")
    }

    private static func loadsInBrowser(_ scheme: String) -> Bool {
        WKWebView.handlesURLScheme(scheme) || scheme == KoalaPage.scheme || scheme == "webkit-extension"
    }
}
