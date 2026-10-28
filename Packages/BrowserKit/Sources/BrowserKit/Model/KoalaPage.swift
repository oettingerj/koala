import AppKit

/// A page Koala draws natively instead of loading in a web view, addressed as `koala://<name>`.
/// The tab keeps the URL, so the address field, history-free navigation, and session restore
/// treat it like any other page.
public enum KoalaPage: String, CaseIterable, Sendable {
    case settings

    public static let scheme = "koala"

    public init?(url: URL?) {
        guard let url, url.scheme?.lowercased() == Self.scheme, let host = url.host()?.lowercased(),
              let page = KoalaPage(rawValue: host) else { return nil }
        self = page
    }

    public var url: URL { URL(string: "\(Self.scheme)://\(rawValue)")! }

    public var title: String {
        switch self {
        case .settings: "Settings"
        }
    }

    /// Stands in for a favicon in the tab strip and command bar.
    @MainActor public var icon: NSImage? {
        let symbol = switch self {
        case .settings: "gearshape"
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .medium))
        image?.isTemplate = true
        return image
    }
}
