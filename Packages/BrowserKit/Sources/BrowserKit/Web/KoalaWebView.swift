import AppKit
import WebKit

/// Every page's web view. It knows which link was right-clicked, so the context menu can offer
/// Koala's link actions next to WebKit's.
public final class KoalaWebView: WKWebView {
    /// A link the user right-clicked.
    public struct ContextLink: Equatable, Sendable {
        public var url: URL
        /// The link's visible text, trimmed; empty for image links.
        public var text: String

        /// Reads the isolated-world script's message: `{href, text}`, or null away from a link.
        public init?(message body: Any) {
            guard let body = body as? [String: Any], let href = body["href"] as? String,
                  let url = URL(string: href), url.scheme == "http" || url.scheme == "https" else { return nil }
            self.url = url
            text = (body["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public private(set) var contextLink: ContextLink?
    /// Called as a context menu opens, with the right-clicked link (nil when there was none).
    public var contextMenuHook: ((NSMenu, ContextLink?) -> Void)?

    override public func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        contextMenuHook?(menu, contextLink)
    }

    // MARK: Link tracking

    static let linkHandler = "koalaContextLink"

    /// Runs in every frame. The page's `contextmenu` event reaches the app before WebKit's menu does.
    static let linkScript = """
    addEventListener('contextmenu', event => {
      const link = event.target instanceof Element ? event.target.closest('a[href]') : null;
      webkit.messageHandlers.\(linkHandler).postMessage(link ? { href: link.href, text: link.innerText || '' } : null);
    }, true);
    """

    /// One handler for the shared configuration; it hands each message to the web view it came from.
    private final class LinkTracker: NSObject, WKScriptMessageHandler {
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            MainActor.assumeIsolated {
                (message.webView as? KoalaWebView)?.contextLink = ContextLink(message: message.body)
            }
        }
    }

    @MainActor private static let tracker = LinkTracker()

    @MainActor static func installLinkTracking(on controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: linkScript, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false, in: DevToolsScripts.world))
        controller.add(tracker, contentWorld: DevToolsScripts.world, name: linkHandler)
    }
}

/// A Markdown link, escaping the brackets that would end its text early.
public func markdownLink(title: String, url: URL) -> String {
    let text = title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    return "[\(text.isEmpty ? url.absoluteString : text)](\(url.absoluteString))"
}
