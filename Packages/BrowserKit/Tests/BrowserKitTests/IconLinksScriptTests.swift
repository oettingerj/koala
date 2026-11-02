import AppKit
import Testing
import WebKit
@testable import BrowserKit

/// Runs the shipped icon-link script in a real web view.
@MainActor @Suite(.serialized) struct IconLinksScriptTests {
    @MainActor private final class Page: NSObject, WKNavigationDelegate {
        let webView: KoalaWebView
        var changes = 0
        var loaded: CheckedContinuation<Void, any Error>?
        override init() {
            webView = WebViewFactory.makeWebView(configuration: WebViewFactory.makePrivateConfiguration()) as! KoalaWebView
            super.init()
            webView.navigationDelegate = self
            webView.iconLinksHook = { [weak self] in self?.changes += 1 }
        }
        func load(_ head: String) async throws {
            try await withCheckedThrowingContinuation { continuation in
                loaded = continuation
                webView.loadHTMLString("<html><head>\(head)</head><body></body></html>", baseURL: URL(string: "https://fixture.koala.test"))
            }
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded?.resume(); loaded = nil }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) { loaded?.resume(throwing: error); loaded = nil }
        /// Runs `source`, waits out the script's debounce, then drains posted messages with a round trip.
        func run(_ source: String) async throws {
            _ = try await webView.callAsyncJavaScript("\(source); await new Promise(r => setTimeout(r, 400)); return true;", contentWorld: .page)
            _ = try await webView.callAsyncJavaScript("return true;", contentWorld: .page)
        }
        func dispose() {
            webView.stopLoading()
            webView.iconLinksHook = nil
        }
    }

    @Test(.timeLimit(.minutes(1))) func reportsIconLinksAddedAfterLoad() async throws {
        _ = NSApplication.shared
        let page = Page(); defer { page.dispose() }
        try await page.load("<title>App</title>")
        try await page.run("document.head.append(document.createElement('div'))")
        #expect(page.changes == 0)
        try await page.run("const l = document.createElement('link'); l.rel = 'icon'; l.href = '/a.png'; document.head.append(l)")
        #expect(page.changes == 1)
        try await page.run("document.querySelector('link').href = '/b.png'")
        #expect(page.changes == 2)
    }

    @Test(.timeLimit(.minutes(1))) func ignoresLinksPresentAtLoad() async throws {
        _ = NSApplication.shared
        let page = Page(); defer { page.dispose() }
        try await page.load("<link rel='icon' href='/a.png'>")
        try await page.run("document.title = 'x'")
        #expect(page.changes == 0)
    }
}
