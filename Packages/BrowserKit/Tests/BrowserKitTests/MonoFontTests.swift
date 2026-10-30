import CoreText
import Foundation
import Testing
@testable import BrowserKit

@Suite struct MonoFontTests {
    @Test func registersBothFacesFromTheBundle() {
        MonoFont.register()
        for name in [MonoFont.regular, MonoFont.bold] {
            #expect(CTFontCopyPostScriptName(CTFontCreateWithName(name as CFString, 12, nil)) as String == name)
        }
    }

    @Test func pagesEmbedTheRegularFace() {
        #expect(MonoFont.cssFontFace.contains("data:font/woff2;base64,"))
        #expect(PageTools.sourcePage(for: "<p>", url: URL(string: "https://example.com")!).contains(MonoFont.cssFontFace))
    }
}
