import Foundation
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
    /// missing or stale. Concurrent requests for one host share a single fetch.
    public func icon(host: String, candidates: [URL]) async -> Data? {
        let fresh = try? await database.writer.read { db -> (Data, Date)? in
            guard let row = try Row.fetchOne(db, sql: "SELECT data, fetchedAt FROM favicon WHERE host = ?", arguments: [host]),
                  let data: Data = row["data"], let date: Date = row["fetchedAt"] else { return nil }
            return (data, date)
        }
        if let (data, fetchedAt) = fresh ?? nil, Date().timeIntervalSince(fetchedAt) < Self.maxAge {
            memory[host] = data
            return data
        }
        if let task = inFlight[host] { return await task.value }
        let task = Task { await download(candidates) }
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

    private func download(_ candidates: [URL]) async -> Data? {
        for url in candidates where url.scheme == "https" || url.scheme == "http" {
            guard let (data, response) = try? await session.data(from: url),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  !data.isEmpty, data.count <= Self.maxBytes,
                  !(http.mimeType ?? "").hasPrefix("text/html") else { continue }
            return data
        }
        return nil
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
            if link.type == "image/svg+xml" || link.href.hasSuffix(".svg") { return 1000 }
            let size = link.sizes.split(separator: "x").first.flatMap { Int($0) } ?? (link.rel.contains("apple") ? 180 : 16)
            // Prefer the smallest icon at least 32px; anything larger is downscaled anyway.
            return size >= 32 ? 900 - size : 100 + size
        }
        var urls = links.filter { score($0) >= 0 }.sorted { score($0) > score($1) }
            .compactMap { URL(string: $0.href, relativeTo: pageURL)?.absoluteURL }
        if let fallback = URL(string: "/favicon.ico", relativeTo: pageURL)?.absoluteURL, !urls.contains(fallback) {
            urls.append(fallback)
        }
        return urls
    }
}
