import Foundation
import GRDB
import Observation

public struct Bookmark: Codable, Equatable, Identifiable, Sendable, FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "bookmark"

    public var id: Int64?
    /// nil means the item sits directly on the bookmarks bar.
    public var parentID: Int64?
    public var title: String
    /// nil for folders.
    public var url: String?
    public var position: Double
    public var createdAt: Date

    public var isFolder: Bool { url == nil }

    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }

    enum CodingKeys: String, CodingKey {
        case id, parentID = "parentId", title, url, position, createdAt
    }
}

/// Live view of the bookmark tree for menus and the bookmarks bar.
@MainActor
@Observable
public final class BookmarkLibrary {
    public private(set) var all: [Bookmark] = []

    @ObservationIgnored private let database: AppDatabase
    @ObservationIgnored private var cancellable: AnyDatabaseCancellable?

    public init(database: AppDatabase) {
        self.database = database
        let observation = ValueObservation.tracking { db in
            try Bookmark.order(Column("position")).fetchAll(db)
        }
        cancellable = observation.start(in: database.writer, scheduling: .immediate) { error in
            assertionFailure("Bookmark observation failed: \(error)")
        } onChange: { [weak self] bookmarks in
            self?.all = bookmarks
        }
    }

    public func children(of parentID: Int64?) -> [Bookmark] {
        all.filter { $0.parentID == parentID }
    }

    public func bookmark(for url: URL) -> Bookmark? {
        let key = url.absoluteString
        return all.first { $0.url == key }
    }

    @discardableResult
    public func add(title: String, url: URL?, in parentID: Int64? = nil) async throws -> Bookmark {
        let siblings = children(of: parentID)
        var bookmark = Bookmark(id: nil, parentID: parentID, title: title, url: url?.absoluteString,
                                position: (siblings.last?.position ?? 0) + 1, createdAt: Date())
        let saved = bookmark
        bookmark = try await database.writer.write { db in
            var row = saved
            try row.insert(db)
            return row
        }
        return bookmark
    }

    public func rename(_ bookmark: Bookmark, to title: String) async throws {
        var updated = bookmark
        updated.title = title
        let row = updated
        try await database.writer.write { db in try row.update(db) }
    }

    public func remove(_ bookmark: Bookmark) async throws {
        _ = try await database.writer.write { db in try bookmark.delete(db) }
    }

    public enum Failure: Error, Equatable { case folderIntoItself }

    /// Moves `bookmark` to `index` among the children of `parentID`.
    /// Throws `folderIntoItself` when `parentID` is the bookmark or lies inside it.
    public func move(_ bookmark: Bookmark, to index: Int, in parentID: Int64?) async throws {
        var siblings = children(of: parentID).filter { $0.id != bookmark.id }
        let clamped = max(0, min(index, siblings.count))
        var moved = bookmark
        moved.parentID = parentID
        siblings.insert(moved, at: clamped)
        let rows = siblings.enumerated().map { offset, item -> Bookmark in
            var row = item
            row.position = Double(offset + 1)
            return row
        }
        try await database.writer.write { db in
            var ancestor = parentID
            while let id = ancestor {
                if id == bookmark.id { throw Failure.folderIntoItself }
                ancestor = try Int64?.fetchOne(db, sql: "SELECT parentId FROM bookmark WHERE id = ?", arguments: [id]) ?? nil
            }
            for row in rows { try row.update(db) }
        }
    }

    /// Bulk insert used by importers. `items` are created in order; folders before their children.
    public func importTree(_ items: [ImportedBookmark], into parentID: Int64? = nil) async throws {
        try await database.writer.write { db in
            func insert(_ nodes: [ImportedBookmark], parent: Int64?, start: Double) throws {
                for (offset, node) in nodes.enumerated() {
                    var row = Bookmark(id: nil, parentID: parent, title: node.title, url: node.url?.absoluteString,
                                       position: start + Double(offset), createdAt: node.createdAt ?? Date())
                    try row.insert(db)
                    if node.url == nil { try insert(node.children, parent: row.id, start: 1) }
                }
            }
            let last = try Double.fetchOne(db, sql: "SELECT MAX(position) FROM bookmark WHERE parentId IS ?",
                                           arguments: [parentID]) ?? 0
            try insert(items, parent: parentID, start: last + 1)
        }
    }
}

/// A bookmark or folder read from another browser, before it is stored.
public struct ImportedBookmark: Equatable, Sendable {
    public var title: String
    public var url: URL?
    public var createdAt: Date?
    public var children: [ImportedBookmark]

    public init(title: String, url: URL?, createdAt: Date? = nil, children: [ImportedBookmark] = []) {
        self.title = title
        self.url = url
        self.createdAt = createdAt
        self.children = children
    }
}
