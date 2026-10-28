import AppKit
import GRDB

/// Favicon bytes per host: memory first, then the database, then the network.
public actor FaviconStore {
    private let database: AppDatabase
    private let session: URLSession
    private var memory: [String: Data] = [:]
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private static let maxAge: TimeInterval = 7 * 86_400
    private static let maxBytes = 512 * 1024

    public init(database: AppDatabase) {
        self.database = database
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        // Cookies come only from WebKit's store, per request (see `download`).
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpAdditionalHeaders = ["Accept": "image/svg+xml,image/png,image/x-icon,image/*;q=0.8"]
        session = URLSession(configuration: config)
    }

    /// Cached icon for `host`, without touching the network.
    public func cached(host: String) async -> Data? {
        if let data = memory[host] { return data }
        let data = try? await database.writer.read { db in
            try Data.fetchOne(db, sql: "SELECT data FROM favicon WHERE host = ?", arguments: [host])
        }
        guard let data else { return nil }
        memory[host] = data
        return data
    }

    /// Returns the icon for `host`, fetching from `candidates` (best first) when the cache is
    /// missing, stale or undecodable. Concurrent requests for one host share a single fetch.
    /// `cookies` gives the cookies to send to a candidate, so icons behind a sign-in load.
    public func icon(host: String, candidates: [URL], cookies: @escaping @Sendable (URL) async -> [HTTPCookie] = { _ in [] }) async -> Data? {
        let fresh = try? await database.writer.read { db -> (Data, Date)? in
            guard let row = try Row.fetchOne(db, sql: "SELECT data, fetchedAt FROM favicon WHERE host = ?", arguments: [host]),
                  let data: Data = row["data"], let date: Date = row["fetchedAt"] else { return nil }
            return (data, date)
        }
        if let (data, fetchedAt) = fresh ?? nil, Date().timeIntervalSince(fetchedAt) < Self.maxAge, Self.decodes(data) {
            memory[host] = data
            return data
        }
        if let task = inFlight[host] { return await task.value }
        let task = Task { await download(candidates, cookies: cookies) }
        inFlight[host] = task
        let data = await task.value
        inFlight[host] = nil
        if let data {
            memory[host] = data
            try? await database.writer.write { db in
                try db.execute(sql: "INSERT OR REPLACE INTO favicon (host, data, fetchedAt) VALUES (?, ?, ?)",
                               arguments: [host, data, Date()])
            }
        }
        return data ?? memory[host]
    }

    /// The first candidate that loads and decodes as an image. A sign-in page or a format AppKit
    /// can't read falls through to the next candidate instead of being cached as the icon.
    private func download(_ candidates: [URL], cookies: @Sendable (URL) async -> [HTTPCookie]) async -> Data? {
        for url in candidates {
            var request = URLRequest(url: url)
            switch url.scheme {
            case "data":
                break
            case "https", "http":
                request.httpShouldHandleCookies = false
                if let header = HTTPCookie.requestHeaderFields(with: await cookies(url))["Cookie"] {
                    request.setValue(header, forHTTPHeaderField: "Cookie")
                }
            default:
                continue
            }
            guard let (data, response) = try? await session.data(for: request, delegate: SameOriginCookies()),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  data.count <= Self.maxBytes, Self.decodes(data) else { continue }
            return data
        }
        return nil
    }

    private static func decodes(_ data: Data) -> Bool {
        NSImage(data: data) != nil
    }
}

/// Keeps a request's cookies on redirects within its origin and drops them on any other, so a
/// redirect to a sign-in page or CDN never carries the site's cookies.
private final class SameOriginCookies: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        var request = request
        let original = task.originalRequest
        let sameOrigin = request.url?.scheme == original?.url?.scheme && request.url?.host() == original?.url?.host()
        request.setValue(sameOrigin ? original?.value(forHTTPHeaderField: "Cookie") : nil, forHTTPHeaderField: "Cookie")
        return request
    }
}

/// Picks favicon URLs from what a page declares, best first, with `/favicon.ico` last.
public enum FaviconCandidates {
    public struct Link: Decodable, Sendable {
        public var href: String
        public var rel: String
        public var sizes: String
        public var type: String
    }

    /// Script returning the page's icon links; runs in an isolated content world.
    public static let script = """
    [...document.querySelectorAll('link[rel~="icon" i], link[rel="apple-touch-icon" i], link[rel="mask-icon" i]')]
      .map(e => ({ href: e.href, rel: (e.rel || '').toLowerCase(), sizes: e.sizes ? e.sizes.value : '', type: e.type || '' }))
    """

    public static func rank(_ links: [Link], pageURL: URL) -> [URL] {
        func score(_ link: Link) -> Int {
            if link.rel.contains("mask-icon") { return -1 } // monochrome; poor in a tab
            if link.type == "image/svg+xml" || link.href.hasSuffix(".svg") || link.href.hasPrefix("data:image/svg+xml") { return 1000 }
            let size = link.sizes.split(separator: "x").first.flatMap { Int($0) } ?? (link.rel.contains("apple") ? 180 : 16)
            // Prefer the smallest icon at least 32px; anything larger is downscaled anyway.
            return size >= 32 ? 900 - size : 100 + size
        }
        var urls = links.filter { score($0) >= 0 }.sorted { score($0) > score($1) }
            .compactMap { dataURL($0.href) ?? URL(string: $0.href, relativeTo: pageURL)?.absoluteURL }
        if let fallback = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL, !urls.contains(fallback) {
            urls.append(fallback)
        }
        return urls
    }

    /// WebKit serializes a `data:` href with its spaces and raw `<` intact, which `URL(string:)`
    /// escapes along with any `%` already there, so `%3C` arrives as `%253C`. Decoding the payload
    /// and re-encoding it as base64 gives a URL that loads as written.
    static func dataURL(_ href: String) -> URL? {
        guard href.lowercased().hasPrefix("data:"), let comma = href.firstIndex(of: ",") else { return nil }
        let header = href[href.index(href.startIndex, offsetBy: 5)..<comma]
        let payload = String(href[href.index(after: comma)...])
        let unescaped = payload.removingPercentEncoding ?? payload
        let bytes = header.lowercased().hasSuffix(";base64")
            ? Data(base64Encoded: unescaped.filter { !$0.isWhitespace })
            : Data(unescaped.utf8)
        guard let bytes else { return nil }
        let type = header.split(separator: ";").first.map(String.init) ?? ""
        return URL(string: "data:\(type);base64,\(bytes.base64EncodedString())")
    }
}
