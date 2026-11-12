import Eucalyptus
import Foundation
import Testing
@testable import BrowserKit

@Suite struct MonoFontPageTests {
    @Test func pagesEmbedTheRegularFace() {
        #expect(PageTools.sourcePage(for: "<p>", url: URL(string: "https://example.com")!).contains(MonoFont.cssFontFace))
    }
}
