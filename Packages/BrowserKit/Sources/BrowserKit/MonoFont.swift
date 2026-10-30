import CoreText
import Foundation

/// 0xProto 2.502 (github.com/0xType/0xProto, SIL Open Font License 1.1, see Fonts/OFL.txt), Koala's
/// monospace face in the chrome and in Koala-authored pages. Only Regular and Bold ship.
public enum MonoFont {
    public static let regular = "0xProto-Regular"
    public static let bold = "0xProto-Bold"

    private static func url(_ name: String) -> URL? {
        Bundle.module.url(forResource: name, withExtension: "woff2", subdirectory: "Fonts")
    }

    /// Registers both faces for this process, so AppKit and SwiftUI resolve them by PostScript name.
    public static func register() {
        for url in [regular, bold].compactMap(url) {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// The CSS font stack for Koala-authored pages. A web content process cannot see fonts the app registers,
    /// so the page carries the face; where a page's CSP blocks data: fonts, the system monospace stands in.
    public static let cssFamily = "'0xProto', ui-monospace, SFMono-Regular, monospace"

    /// An `@font-face` rule that embeds the Regular face as a data URL. Koala's pages never set mono in bold.
    public static let cssFontFace: String = {
        guard let url = url(regular), let data = try? Data(contentsOf: url) else { return "" }
        return "@font-face { font-family: '0xProto'; font-weight: 400; src: url(data:font/woff2;base64,\(data.base64EncodedString())) format('woff2'); }"
    }()
}
