import Foundation

/// A site search reachable by typing its keyword and a space: "mdn flexbox".
public struct KeywordSearch: Codable, Equatable, Identifiable, Sendable {
    public var keyword: String
    public var name: String
    /// URL with `%s` where the encoded query goes.
    public var template: String

    public var id: String { keyword }

    public init(keyword: String, name: String, template: String) {
        self.keyword = keyword
        self.name = name
        self.template = template
    }

    public func url(for query: String) -> URL? {
        AddressInput.searchURL(for: query, template: template)
    }

    public static let defaults: [KeywordSearch] = [
        KeywordSearch(keyword: "gh", name: "GitHub", template: "https://github.com/search?q=%s&type=repositories"),
        KeywordSearch(keyword: "mdn", name: "MDN", template: "https://developer.mozilla.org/en-US/search?q=%s"),
        KeywordSearch(keyword: "npm", name: "npm", template: "https://www.npmjs.com/search?q=%s"),
        KeywordSearch(keyword: "crates", name: "crates.io", template: "https://crates.io/search?q=%s"),
        KeywordSearch(keyword: "pypi", name: "PyPI", template: "https://pypi.org/search/?q=%s"),
        KeywordSearch(keyword: "go", name: "Go Packages", template: "https://pkg.go.dev/search?q=%s"),
        KeywordSearch(keyword: "so", name: "Stack Overflow", template: "https://stackoverflow.com/search?q=%s"),
        KeywordSearch(keyword: "docs", name: "DevDocs", template: "https://devdocs.io/#q=%s"),
        KeywordSearch(keyword: "spi", name: "Swift Package Index", template: "https://swiftpackageindex.com/search?query=%s"),
    ]

    /// Splits "mdn flexbox" into the matching search and "flexbox". The query may be empty
    /// when the user has typed only the keyword and a space.
    public static func match(_ text: String, in searches: [KeywordSearch]) -> (KeywordSearch, String)? {
        guard let space = text.firstIndex(of: " ") else { return nil }
        let keyword = text[..<space].lowercased()
        guard let search = searches.first(where: { $0.keyword == keyword }) else { return nil }
        return (search, String(text[text.index(after: space)...]).trimmingCharacters(in: .whitespaces))
    }
}
