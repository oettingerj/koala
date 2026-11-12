import Eucalyptus
import Foundation
import GRDB

/// Koala's SQLite database: history (with full-text search), bookmarks, favicons, and pull request summaries.
/// Reads and writes happen off the main thread; UI models observe it.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// The on-disk database in Koala's Application Support folder.
    public static func openDefault() throws -> AppDatabase {
        let directory = try AppSupport.directory()
        var config = Configuration()
        config.qos = .userInitiated
        let pool = try DatabasePool(path: directory.appendingPathComponent("koala.sqlite").path, configuration: config)
        return try AppDatabase(pool)
    }

    public static func inMemory() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue())
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("url", .text).notNull().unique()
                t.column("title", .text).notNull().defaults(to: "")
                t.column("host", .text).notNull().indexed()
                t.column("visitCount", .integer).notNull().defaults(to: 0)
                t.column("typedCount", .integer).notNull().defaults(to: 0)
                t.column("lastVisitedAt", .datetime).notNull().indexed()
            }
            try db.create(virtualTable: "history_fts", using: FTS5()) { t in
                t.synchronize(withTable: "history")
                t.tokenizer = .unicode61()
                t.prefixes = [2, 3]
                t.column("title")
                t.column("url")
            }
            try db.create(table: "bookmark") { t in
                t.autoIncrementedPrimaryKey("id")
                t.belongsTo("parent", inTable: "bookmark", onDelete: .cascade)
                t.column("title", .text).notNull()
                t.column("url", .text)
                t.column("position", .double).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(table: "favicon") { t in
                t.primaryKey("host", .text)
                t.column("data", .blob).notNull()
                t.column("fetchedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v2") { db in
            try db.create(table: "pullSummary") { t in
                t.primaryKey("id", .text)
                t.column("fingerprint", .text).notNull()
                t.column("gist", .text).notNull()
                t.column("overview", .text).notNull()
                t.column("generatedAt", .datetime).notNull().indexed()
            }
        }
        return migrator
    }
}
