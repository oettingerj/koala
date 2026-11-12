import Eucalyptus
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

    /// Certificate failures the user may choose to accept for the rest of the session.
    public static func isCertificateError(_ error: Error) -> Bool {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return false }
        return [NSURLErrorServerCertificateUntrusted, NSURLErrorServerCertificateHasBadDate,
                NSURLErrorServerCertificateHasUnknownRoot, NSURLErrorServerCertificateNotYetValid].contains(nsError.code)
    }

    /// A local server that isn't listening yet, usually a dev server that is starting or restarting.
    /// The tab reloads on its own once something answers.
    public static func waitsForServer(_ url: URL, error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCannotConnectToHost && url.isLoopback
    }

    /// The "Visit Anyway" link on a certificate error. The tab honors it only from its own error page.
    public static let proceedURL = URL(string: "koala://proceed")!

    public static func html(for url: URL, error: Error) -> String {
        let host = DisplayURL(url)?.host ?? url.absoluteString
        let nsError = error as NSError
        let headline: String
        var note: String?
        var proceeds = false
        switch nsError.code {
        case NSURLErrorCannotConnectToHost: headline = "Nothing is answering at \(host)"
        case NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed: headline = "Can’t find \(host)"
        case NSURLErrorNotConnectedToInternet: headline = "You’re offline"
        case NSURLErrorTimedOut: headline = "\(host) took too long to respond"
        case _ where isCertificateError(error):
            headline = "\(host)’s certificate isn’t trusted"
            note = "Someone could be impersonating this site. Visit it only if you know why its certificate isn’t trusted, like a local development certificate."
            proceeds = true
        default: headline = "Can’t open \(host)"
        }
        if waitsForServer(url, error: error) { note = "Koala reloads this page when the server starts." }
        let detail = "\(nsError.localizedDescription) (\(nsError.domain) \(nsError.code))"
        return page(headline: headline, detail: detail, note: note, url: url, proceeds: proceeds)
    }

    /// The page shown when a tab's web content process crashes again right after recovering.
    public static func crashed(_ url: URL) -> String {
        page(headline: "This page crashed", detail: "Its web content process quit twice in a row.",
             note: nil, url: url, proceeds: false)
    }

    private static func page(headline: String, detail: String, note: String?, url: URL, proceeds: Bool) -> String {
        let noteHTML = note.map { "<p class=\"note\">\(escape($0))</p>" } ?? ""
        let proceedHTML = proceeds ? "<a class=\"proceed\" href=\"\(proceedURL.absoluteString)\">Visit Anyway</a>" : ""
        return """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>\(escape(headline))</title>
        <meta name="color-scheme" content="light dark">
        <style>\(MonoFont.cssFontFace)
          :root { --bg: #FAFAFA; --fg: #18181B; --muted: #6C6C75; --rule: #DEDEE1; --accent: #0B7A6D; --on-accent: #FFFFFF; }
          @media (prefers-color-scheme: dark) {
            :root { --bg: #1E1E21; --fg: #F4F4F5; --muted: #8A8A93; --rule: #303035; --accent: #2CC3AE; --on-accent: #0B1F1C; }
          }
          html { background: var(--bg); color: var(--fg); font: 13px/1.5 -apple-system, system-ui, sans-serif; }
          body { margin: 0; min-height: 100vh; display: grid; place-items: center; }
          main { width: min(520px, calc(100vw - 48px)); }
          h1 { font-size: 20px; font-weight: 600; letter-spacing: -0.01em; margin: 0 0 8px; }
          p { margin: 0 0 4px; color: var(--muted); }
          p.note { margin-top: 8px; color: var(--fg); }
          code { font: 12px/1.5 \(MonoFont.cssFamily); color: var(--muted); word-break: break-all; }
          .url { display: block; margin: 16px 0 20px; padding-top: 12px; border-top: 1px solid var(--rule); }
          a.retry { display: inline-block; padding: 5px 12px; border-radius: 6px; background: var(--accent);
                    color: var(--on-accent); text-decoration: none; font-weight: 500; }
          a.proceed { margin-left: 12px; color: var(--muted); }
          a:focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; }
          ::selection { background: color-mix(in srgb, var(--accent) 30%, transparent); }
        </style></head>
        <body><main>
          <h1>\(escape(headline))</h1>
          <p>\(escape(detail))</p>
          \(noteHTML)
          <code class="url">\(escape(url.absoluteString))</code>
          <a class="retry" href="\(escape(url.absoluteString))">Try Again</a>\(proceedHTML)
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
