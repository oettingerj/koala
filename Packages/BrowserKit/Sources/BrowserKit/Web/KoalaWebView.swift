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
    /// Called when the page changes its icon links after it loaded, as client-rendered apps do.
    public var iconLinksHook: (() -> Void)?

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

    // MARK: Icon link tracking

    static let iconLinksHandler = "koalaIconLinks"

    /// Runs in the main frame. Links present at `load` are read when the navigation finishes, so
    /// this reports only later changes, such as a client-rendered app adding its icon on mount.
    static let iconLinksScript = """
    addEventListener('load', () => {
      const signature = () => [...document.querySelectorAll('\(FaviconCandidates.selector)')]
        .map(e => e.rel + ' ' + e.href).join('\\n');
      let last = signature(), timer = 0;
      new MutationObserver(() => {
        timer ||= setTimeout(() => {
          timer = 0;
          const now = signature();
          if (now !== last) { last = now; webkit.messageHandlers.\(iconLinksHandler).postMessage(null); }
        }, 250);
      }).observe(document.head ?? document.documentElement,
                 { childList: true, subtree: true, attributes: true, attributeFilter: ['href', 'rel'] });
    }, { once: true });
    """

    /// One handler for the shared configuration; it hands each message to the web view it came from.
    private final class PageMessages: NSObject, WKScriptMessageHandler {
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            MainActor.assumeIsolated {
                guard let webView = message.webView as? KoalaWebView else { return }
                switch message.name {
                case linkHandler: webView.contextLink = ContextLink(message: message.body)
                case iconLinksHandler: webView.iconLinksHook?()
                default: break
                }
            }
        }
    }

    @MainActor private static let messages = PageMessages()

    @MainActor static func installPageTracking(on controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: linkScript, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false, in: DevToolsScripts.world))
        controller.addUserScript(WKUserScript(source: iconLinksScript, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: true, in: DevToolsScripts.world))
        controller.add(messages, contentWorld: DevToolsScripts.world, name: linkHandler)
        controller.add(messages, contentWorld: DevToolsScripts.world, name: iconLinksHandler)
    }
}

/// A Markdown link, escaping the brackets that would end its text early.
public func markdownLink(title: String, url: URL) -> String {
    let text = title.replacingOccurrences(of: "[", with: "\\[").replacingOccurrences(of: "]", with: "\\]")
    return "[\(text.isEmpty ? url.absoluteString : text)](\(url.absoluteString))"
}
