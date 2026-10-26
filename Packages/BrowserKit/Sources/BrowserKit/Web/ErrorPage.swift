import Foundation

/// The page shown when a navigation fails before any content arrives.
public enum ErrorPage {
    /// Errors that are not failures from the user's point of view: a cancelled load,
    /// a navigation replaced by another, or a response handed to the download system.
    public static func isSilent(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
        // WebKitErrorFrameLoadInterruptedByPolicyChange
        if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { return true }
        return false
    }

    public static func html(for url: URL, error: Error) -> String {
        let host = DisplayURL(url)?.host ?? url.absoluteString
        let nsError = error as NSError
        let headline: String
        switch nsError.code {
        case NSURLErrorCannotConnectToHost: headline = "Nothing is answering at \(host)"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: headline = "Can’t find \(host)"
        case NSURLErrorNotConnectedToInternet: headline = "You’re offline"
        case NSURLErrorTimedOut: headline = "\(host) took too long to respond"
        case NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
             NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid:
            headline = "\(host)’s certificate isn’t trusted"
        default: headline = "Can’t open \(host)"
        }
        let detail = "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(escape(headline))</title>
        <meta name="color-scheme" content="light dark">
        <style>
          :root { --bg: #FAFAFA; --fg: #18181B; --muted: #6C6C75; --rule: #DEDEE1; --accent: #0E8F80; }
          @media (prefers-color-scheme: dark) {
            :root { --bg: #1E1E21; --fg: #F4F4F5; --muted: #8A8A93; --rule: #303035; --accent: #2CC3AE; }
          }
          html { background: var(--bg); color: var(--fg); font: 13px/1.5 -apple-system, system-ui, sans-serif; }
          body { margin: 0; min-height: 100vh; display: grid; place-items: center; }
          main { width: min(520px, calc(100vw - 48px)); }
          h1 { font-size: 20px; font-weight: 600; letter-spacing: -0.01em; margin: 0 0 8px; }
          p { margin: 0 0 4px; color: var(--muted); }
          code { font: 12px/1.5 ui-monospace, SFMono-Regular, monospace; color: var(--muted); word-break: break-all; }
          .url { display: block; margin: 16px 0 20px; padding-top: 12px; border-top: 1px solid var(--rule); }
          a.retry { display: inline-block; padding: 5px 12px; border-radius: 6px; background: var(--accent);
                    color: #fff; text-decoration: none; font-weight: 500; }
          a.retry:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
          ::selection { background: color-mix(in srgb, var(--accent) 30%, transparent); }
        </style></head>
        <body><main>
          <h1>\(escape(headline))</h1>
          <p>\(escape(detail))</p>
          <code class="url">\(escape(url.absoluteString))</code>
          <a class="retry" href="\(escape(url.absoluteString))">Try Again</a>
        </main></body></html>
        """
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
