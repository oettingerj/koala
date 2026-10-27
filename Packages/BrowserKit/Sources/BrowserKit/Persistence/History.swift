import Foundation
import GRDB

public struct HistoryEntry: Codable, Equatable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "history"

    public var id: Int64?
    public var url: String
    public var title: String
    public var host: String
    public var visitCount: Int
    public var typedCount: Int
    public var lastVisitedAt: Date

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    /// Frecency: visits weighted by how recently the page was seen, typed visits counting double.
    public func score(now: Date = Date()) -> Double {
        let days = max(0, now.timeIntervalSince(lastVisitedAt)) / 86_400
        let recency = days < 1 ? 1.0 : days < 7 ? 0.7 : days < 30 ? 0.4 : days < 90 ? 0.2 : 0.1
        return Double(visitCount + typedCount * 2) * recency
    }
}

/// Records and searches browsing history.
public struct HistoryStore: Sendable {
    let database: AppDatabase

    public init(database: AppDatabase) { self.database = database }

    /// Pages Nano never records: its own error pages, blank pages, and non-web schemes.
    static func isRecordable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    public func recordVisit(url: URL, title: String, typed: Bool = false, at date: Date = Date()) async throws {
        guard Self.isRecordable(url) else { return }
        let key = url.absoluteString
        let host = DisplayURL(url)?.host ?? ""
        try await database.writer.write { db in
            if var entry = try HistoryEntry.filter(Column("url") == key).fetchOne(db) {
                entry.visitCount += 1
                if typed { entry.typedCount += 1 }
                entry.lastVisitedAt = date
                if !title.isEmpty { entry.title = title }
                try entry.update(db)
            } else {
                var entry = HistoryEntry(id: nil, url: key, title: title, host: host, visitCount: 1,
                                         typedCount: typed ? 1 : 0, lastVisitedAt: date)
                try entry.insert(db)
            }
        }
    }

    public func updateTitle(url: URL, title: String) async throws {
        guard Self.isRecordable(url), !title.isEmpty else { return }
        let key = url.absoluteString
        try await database.writer.write { db in
            try HistoryEntry.filter(Column("url") == key).updateAll(db, Column("title").set(to: title))
        }
    }

    /// Full-text prefix search over titles and URLs, ranked by frecency.
    public func search(_ text: String, limit: Int = 8) async throws -> [HistoryEntry] {
        guard let pattern = Self.prefixPattern(text) else { return [] }
        let candidates = try await database.writer.read { db in
            try HistoryEntry.fetchAll(db, sql: """
                SELECT history.* FROM history
                JOIN history_fts ON history_fts.rowid = history.id AND history_fts MATCH ?
                ORDER BY bm25(history_fts) LIMIT 200
                """, arguments: [pattern])
        }
        let now = Date()
        return Array(candidates.sorted { $0.score(now: now) > $1.score(now: now) }.prefix(limit))
    }

    public func recent(limit: Int = 50) async throws -> [HistoryEntry] {
        try await database.writer.read { db in
            try HistoryEntry.order(Column("lastVisitedAt").desc).limit(limit).fetchAll(db)
        }
    }

    /// Synchronous read for menus, which must be filled before they open. Cheap: one indexed query.
    public func recentNow(limit: Int = 15) -> [HistoryEntry] {
        (try? database.writer.read { db in
            try HistoryEntry.order(Column("lastVisitedAt").desc).limit(limit).fetchAll(db)
        }) ?? []
    }

    public func delete(_ entry: HistoryEntry) async throws {
        _ = try await database.writer.write { db in try entry.delete(db) }
    }

    public func clear(since date: Date? = nil) async throws {
        try await database.writer.write { db in
            if let date {
                try HistoryEntry.filter(Column("lastVisitedAt") >= date).deleteAll(db)
            } else {
                try HistoryEntry.deleteAll(db)
            }
        }
    }

    /// Every typed token becomes a prefix term: "gh swi" matches "GitHub - swiftlang/swift".
    static func prefixPattern(_ text: String) -> String? {
        let tokens = text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}
