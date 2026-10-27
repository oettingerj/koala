import Foundation
import GRDB

/// Nano's SQLite database: history (with full-text search), bookmarks, and favicons.
/// Reads and writes happen off the main thread; UI models observe it.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter

    public init(_ writer: any DatabaseWriter) throws {
        self.writer = writer
        try Self.migrator.migrate(writer)
    }

    /// The on-disk database in Application Support (inside the sandbox container).
    public static func openDefault() throws -> AppDatabase {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
            .appendingPathComponent("Nano", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var config = Configuration()
        config.qos = .userInitiated
        let pool = try DatabasePool(path: directory.appendingPathComponent("nano.sqlite").path, configuration: config)
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
        return migrator
    }
}
