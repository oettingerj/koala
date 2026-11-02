import Foundation
import GRDB

/// What a pull request is about, written on this Mac: a one-line gist for its row and a few
/// sentences for the detail pane.
public struct PullSummary: Equatable, Sendable {
    public var gist: String
    public var overview: String
    public init(gist: String, overview: String) { self.gist = gist; self.overview = overview }
}

/// Summaries kept across launches, each under the fingerprint of the text it was made from, so a
/// pull request is summarized again only when its title, description, or files change.
public final class PullSummaryStore: Sendable {
    private let database: AppDatabase
    private static let maxAge: TimeInterval = 30 * 86_400

    public init(database: AppDatabase) { self.database = database }

    /// Stored summaries for `ids`, with the fingerprint each was made from.
    public func load(_ ids: [String]) async -> [String: (fingerprint: String, summary: PullSummary)] {
        guard !ids.isEmpty else { return [:] }
        let rows = (try? await database.writer.read { db in
            try Row.fetchAll(db, sql: "SELECT id, fingerprint, gist, overview FROM pullSummary WHERE id IN (\(databaseQuestionMarks(count: ids.count)))",
                             arguments: StatementArguments(ids))
                .map { row -> (id: String, fingerprint: String, summary: PullSummary) in
                    (row["id"], row["fingerprint"], PullSummary(gist: row["gist"], overview: row["overview"]))
                }
        }) ?? []
        return Dictionary(rows.map { ($0.id, ($0.fingerprint, $0.summary)) }) { _, new in new }
    }

    public func save(id: String, fingerprint: String, summary: PullSummary) async {
        try? await database.writer.write { db in
            try db.execute(sql: "INSERT OR REPLACE INTO pullSummary (id, fingerprint, gist, overview, generatedAt) VALUES (?, ?, ?, ?, ?)",
                           arguments: [id, fingerprint, summary.gist, summary.overview, Date()])
        }
    }

    /// Forgets summaries older than 30 days of pull requests no longer in the lists.
    public func prune(keeping ids: [String]) async {
        let cutoff = Date().addingTimeInterval(-Self.maxAge)
        try? await database.writer.write { db in
            if ids.isEmpty {
                try db.execute(sql: "DELETE FROM pullSummary WHERE generatedAt < ?", arguments: [cutoff])
            } else {
                try db.execute(sql: "DELETE FROM pullSummary WHERE generatedAt < ? AND id NOT IN (\(databaseQuestionMarks(count: ids.count)))",
                               arguments: StatementArguments([cutoff as any DatabaseValueConvertible] + ids.map { $0 as any DatabaseValueConvertible }))
            }
        }
    }
}
