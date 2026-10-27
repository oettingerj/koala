import Foundation
import GRDB

/// Reads bookmarks and history exported by other browsers. Files are chosen by the user
/// (the sandbox grants access to what they pick), so parsers never touch other paths.
public enum BookmarkImporters {
    public enum Failure: Error, Equatable { case unrecognized }

    /// Detects the format from the file's contents.
    public static func bookmarks(from data: Data) throws -> [ImportedBookmark] {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if json["roots"] != nil { return chrome(json) }
            if json["sidebar"] != nil { return arc(json) }
        }
        if let html = String(data: data, encoding: .utf8), html.localizedCaseInsensitiveContains("<DL") {
            return netscape(html)
        }
        throw Failure.unrecognized
    }

    // MARK: Chrome, Edge, Brave (Bookmarks JSON)

    static func chrome(_ json: [String: Any]) -> [ImportedBookmark] {
        let roots = json["roots"] as? [String: Any] ?? [:]
        func node(_ value: Any?) -> ImportedBookmark? {
            guard let dict = value as? [String: Any], let name = dict["name"] as? String else { return nil }
            let created = (dict["date_added"] as? String).flatMap(Double.init).map(webKitDate)
            if dict["type"] as? String == "url" {
                guard let url = (dict["url"] as? String).flatMap(URL.init(string:)), isWeb(url) else { return nil }
                return ImportedBookmark(title: name, url: url, createdAt: created)
            }
            let children = (dict["children"] as? [Any] ?? []).compactMap(node)
            return ImportedBookmark(title: name, url: nil, createdAt: created, children: children)
        }
        var result: [ImportedBookmark] = []
        // The bar's contents go on Nano's bar directly; other roots become folders.
        if let bar = node(roots["bookmark_bar"]) { result.append(contentsOf: bar.children) }
        for key in ["other", "synced"] {
            if let folder = node(roots[key]), !folder.children.isEmpty { result.append(folder) }
        }
        return result
    }

    /// Chrome stores microseconds since 1601-01-01.
    static func webKitDate(_ microseconds: Double) -> Date {
        Date(timeIntervalSince1970: microseconds / 1_000_000 - 11_644_473_600)
    }

    // MARK: Safari, Firefox, and any "Export Bookmarks" HTML (Netscape format)

    static func netscape(_ html: String) -> [ImportedBookmark] {
        // Tokenize the tags that matter; the format is too loose for an XML parser.
        let pattern = /(?i)<DT><H3[^>]*>(.*?)<\/H3>|<DT><A\s+([^>]*)>(.*?)<\/A>|<DL>|<\/DL>/
        var stack: [[ImportedBookmark]] = [[]]
        var titles: [String] = []
        var pendingFolder: String?
        for match in html.matches(of: pattern) {
            let token = String(match.output.0).uppercased()
            if let folder = match.output.1 {
                pendingFolder = decode(String(folder))
            } else if let attributes = match.output.2, let title = match.output.3 {
                guard let href = attribute("HREF", in: String(attributes)), let url = URL(string: href), isWeb(url) else { continue }
                let created = attribute("ADD_DATE", in: String(attributes)).flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
                stack[stack.count - 1].append(ImportedBookmark(title: decode(String(title)), url: url, createdAt: created))
            } else if token == "<DL>" {
                stack.append([])
                titles.append(pendingFolder ?? "")
                pendingFolder = nil
            } else if token == "</DL>", stack.count > 1 {
                let children = stack.removeLast()
                let title = titles.removeLast()
                if title.isEmpty {
                    stack[stack.count - 1].append(contentsOf: children)
                } else {
                    stack[stack.count - 1].append(ImportedBookmark(title: title, url: nil, children: children))
                }
            }
        }
        var result = stack.first ?? []
        // Safari wraps everything in a "Favorites"/"Bookmarks Bar" folder: unwrap a lone root.
        if result.count == 1, result[0].url == nil { result = result[0].children }
        return result
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        let pattern = try! Regex("(?i)\(name)=\"([^\"]*)\"")
        guard let match = attributes.firstMatch(of: pattern), let value = match.output[1].substring else { return nil }
        return decode(String(value))
    }

    private static func decode(_ text: String) -> String {
        text.replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }

    // MARK: Arc (StorableSidebar.json)

    static func arc(_ json: [String: Any]) -> [ImportedBookmark] {
        let containers = (json["sidebar"] as? [String: Any])?["containers"] as? [Any] ?? []
        // Items alternate id strings and item objects; keep the objects.
        var items: [String: [String: Any]] = [:]
        for container in containers {
            for case let item as [String: Any] in (container as? [String: Any])?["items"] as? [Any] ?? [] {
                if let id = item["id"] as? String { items[id] = item }
            }
        }
        func build(_ id: String) -> ImportedBookmark? {
            guard let item = items[id], let data = item["data"] as? [String: Any] else { return nil }
            let children = (item["childrenIds"] as? [String] ?? []).compactMap(build)
            if let tab = data["tab"] as? [String: Any] {
                guard let url = (tab["savedURL"] as? String).flatMap(URL.init(string:)), isWeb(url) else { return nil }
                let title = (item["title"] as? String) ?? (tab["savedTitle"] as? String) ?? url.absoluteString
                return ImportedBookmark(title: title, url: url)
            }
            let title = (item["title"] as? String) ?? ""
            if data["list"] != nil, !children.isEmpty { return ImportedBookmark(title: title.isEmpty ? "Folder" : title, url: nil, children: children) }
            // Space containers (pinned, unpinned) are structural; flatten them.
            return children.isEmpty ? nil : ImportedBookmark(title: title, url: nil, children: children)
        }
        let roots = items.values.filter { ($0["parentID"] as? String).map { items[$0] == nil } ?? true }
            .compactMap { ($0["id"] as? String).flatMap(build) }
        let flattened = roots.flatMap { $0.title.isEmpty ? $0.children : [$0] }
        return flattened.isEmpty ? [] : [ImportedBookmark(title: "Arc", url: nil, children: flattened)]
    }

    private static func isWeb(_ url: URL) -> Bool {
        url.scheme == "http" || url.scheme == "https"
    }
}

/// Copies visits from a Chrome `History` database into Nano's history.
public enum ChromeHistoryImporter {
    public static func entries(fromDatabaseAt url: URL, limit: Int = 20_000) throws -> [HistoryEntry] {
        // Chrome keeps the file locked while running: read a copy.
        let copy = FileManager.default.temporaryDirectory.appendingPathComponent("chrome-history-\(UUID().uuidString).sqlite")
        try FileManager.default.copyItem(at: url, to: copy)
        defer { try? FileManager.default.removeItem(at: copy) }
        var config = Configuration()
        config.readonly = true
        let queue = try DatabaseQueue(path: copy.path, configuration: config)
        return try queue.read { db in
            try Row.fetchAll(db, sql: """
                SELECT url, title, visit_count, typed_count, last_visit_time FROM urls
                WHERE hidden = 0 ORDER BY last_visit_time DESC LIMIT ?
                """, arguments: [limit]).compactMap { row in
                guard let string: String = row["url"], let parsed = URL(string: string),
                      parsed.scheme == "http" || parsed.scheme == "https" else { return nil }
                return HistoryEntry(id: nil, url: string, title: row["title"] ?? "", host: DisplayURL(parsed)?.host ?? "",
                                    visitCount: row["visit_count"] ?? 1, typedCount: row["typed_count"] ?? 0,
                                    lastVisitedAt: BookmarkImporters.webKitDate(Double(row["last_visit_time"] as Int64? ?? 0)))
            }
        }
    }
}

extension HistoryStore {
    /// Merges imported entries: counts add up, the latest visit and a non-empty title win.
    public func importEntries(_ entries: [HistoryEntry]) async throws {
        try await database.writer.write { db in
            for imported in entries {
                if var existing = try HistoryEntry.filter(Column("url") == imported.url).fetchOne(db) {
                    existing.visitCount += imported.visitCount
                    existing.typedCount += imported.typedCount
                    existing.lastVisitedAt = max(existing.lastVisitedAt, imported.lastVisitedAt)
                    if existing.title.isEmpty { existing.title = imported.title }
                    try existing.update(db)
                } else {
                    var row = imported
                    try row.insert(db)
                }
            }
        }
    }
}
