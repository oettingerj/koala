import Foundation
import Testing
@testable import BrowserKit

@MainActor
@Suite struct KoalaPageTests {
    @Test func parsesOnlyKnownPages() {
        #expect(KoalaPage(url: URL(string: "koala://settings")) == .settings)
        #expect(KoalaPage(url: URL(string: "KOALA://Settings")) == .settings)
        #expect(KoalaPage(url: URL(string: "koala://nope")) == nil)
        #expect(KoalaPage(url: URL(string: "https://settings")) == nil)
        #expect(KoalaPage.settings.url.absoluteString == "koala://settings")
        #expect(KoalaPage(url: URL(string: "koala://history")) == .history)
        #expect(KoalaPage(url: URL(string: "koala://bookmarks")) == .bookmarks)
    }

    @Test func nativeTabNeverCreatesAWebView() {
        let tab = Tab(url: KoalaPage.settings.url)
        #expect(tab.page == .settings)
        #expect(tab.title == "Settings")
        #expect(tab.favicon != nil)
        tab.reload()
        #expect(tab.webView == nil)
    }

    @Test func loadingANativePageReleasesTheWebView() {
        let tab = Tab(url: URL(string: "about:blank"))
        tab.materialize()
        tab.load(KoalaPage.settings.url)
        #expect(tab.webView == nil)
        #expect(tab.title == "Settings")
        #expect(!tab.canGoBack)
    }

    @Test func leavingANativePageLoadsTheWeb() {
        let tab = Tab(url: KoalaPage.settings.url)
        tab.load(URL(string: "about:blank")!)
        #expect(tab.page == nil)
        #expect(tab.webView != nil)
    }

    @Test func snapshotRestoresTheNativePage() {
        let restored = Tab(snapshot: Tab(url: KoalaPage.settings.url).snapshot)
        #expect(restored.page == .settings)
        #expect(restored.title == "Settings")
        #expect(restored.webView == nil)
    }

    @Test func cachedFaviconNeverReplacesThePageIcon() {
        let tab = Tab(url: KoalaPage.settings.url)
        let icon = tab.favicon
        tab.setFavicon(nil)
        #expect(tab.favicon === icon)
    }
}
