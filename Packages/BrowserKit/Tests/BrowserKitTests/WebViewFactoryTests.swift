import Foundation
import Testing
import WebKit
@testable import BrowserKit

@MainActor struct WebViewFactoryTests {
    /// Safari's version tracks the OS. A stale one makes bot checks challenge the page again.
    @Test func userAgentClaimsTheRunningSafariVersion() {
        let major = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        #expect(WebViewFactory.safariVersion.hasPrefix("\(major)."))
        #expect(WebViewFactory.configuration.applicationNameForUserAgent
            == "Version/\(WebViewFactory.safariVersion) Safari/605.1.15")
    }
}
