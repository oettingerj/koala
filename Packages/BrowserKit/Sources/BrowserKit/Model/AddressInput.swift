import Foundation

/// Turns whatever the user typed into the address field into a URL to load.
public enum AddressInput {
    public static let defaultSearchTemplate = "https://www.google.com/search?q=%s"

    public static func resolve(_ raw: String, searchTemplate: String = defaultSearchTemplate) -> URL? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let url = explicitURL(text) { return url }
        if !text.contains(" "), let url = hostLikeURL(text) { return url }
        return searchURL(for: text, template: searchTemplate)
    }

    public static func searchURL(for query: String, template: String = defaultSearchTemplate) -> URL? {
        guard let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) else { return nil }
        return URL(string: template.replacingOccurrences(of: "%s", with: encoded))
    }

    private static let knownSchemes: Set<String> = ["http", "https", "file", "about", "data", "view-source", KoalaPage.scheme]

    private static func explicitURL(_ text: String) -> URL? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let scheme = text[..<colon].lowercased()
        guard knownSchemes.contains(scheme), !text.contains(" ") else { return nil }
        // "localhost:3000" parses as scheme "localhost"; only accept real schemes.
        return URL(string: text)
    }

    private static func hostLikeURL(_ text: String) -> URL? {
        let hostPart = text.split(separator: "/", maxSplits: 1).first.map(String.init) ?? text
        let host = hostPart.split(separator: ":", maxSplits: 1).first.map(String.init)?.lowercased() ?? hostPart

        let isLocal = host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".test") || isIPv4(host)
        let looksLikeDomain = host.contains(".") && !host.hasPrefix(".") && !host.hasSuffix(".")
            && host.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }
            && (host.split(separator: ".").last.map { isKnownTLD(String($0)) } ?? false)

        guard isLocal || looksLikeDomain else { return nil }
        return URL(string: (isLocal ? "http://" : "https://") + text)
    }

    /// Two-letter country codes plus the generic TLDs people actually type. Keeps
    /// "Package.swift" or "main.cpp" a search rather than a dead navigation.
    private static let genericTLDs: Set<String> = [
        "com", "org", "net", "edu", "gov", "mil", "int", "dev", "app", "page", "io", "info", "biz",
        "xyz", "tech", "site", "online", "cloud", "blog", "art", "design", "codes", "software",
        "tools", "systems", "studio", "network", "zone", "run", "build", "new", "inc", "llc", "ltd",
        "company", "email", "link", "live", "news", "shop", "store", "wiki", "website", "space", "fun",
        "google", "apple", "amazon", "microsoft", "local", "internal", "home", "lan", "onion",
    ]

    private static func isKnownTLD(_ tld: String) -> Bool {
        (tld.count == 2 && tld.allSatisfy(\.isLetter)) || genericTLDs.contains(tld)
    }

    private static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { UInt8($0) != nil }
    }
}

extension CharacterSet {
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&+=?#")
        return set
    }()
}
