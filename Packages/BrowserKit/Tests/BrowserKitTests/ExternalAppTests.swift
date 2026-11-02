import Foundation
import Testing
@testable import BrowserKit

@Suite @MainActor struct ExternalAppTests {
    @Test func webAndNativeSchemesStayInTheBrowser() {
        for link in ["https://zoom.us/j/123", "http://localhost:3000", "about:blank", "data:text/plain,hi",
                     "file:///tmp/a.html", "koala://settings", "webkit-extension://abc/popup.html"] {
            #expect(ExternalApp.handler(for: URL(string: link)!) == nil, "\(link)")
        }
    }

    @Test func appSchemesGoToTheirApp() {
        // Mail ships with macOS, so mailto: always has a handler.
        #expect(ExternalApp.handler(for: URL(string: "mailto:someone@example.com")!) != nil)
        #expect(ExternalApp.handler(for: URL(string: "koala-test-unregistered-scheme://x")!) == nil)
    }
}
