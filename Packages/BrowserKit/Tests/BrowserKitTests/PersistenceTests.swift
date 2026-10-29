import Foundation
import Testing
@testable import BrowserKit

@Suite struct HistoryTests {
    @Test func searchMatchesTokenPrefixesAndRanksByFrecency() async throws {
        let history = HistoryStore(database: try .inMemory())
        let now = Date()
        try await history.recordVisit(url: URL(string: "https://github.com/swiftlang/swift")!, title: "GitHub - swiftlang/swift", at: now)
        for _ in 0..<5 {
            try await history.recordVisit(url: URL(string: "https://github.com/swiftlang/swift-format")!, title: "swift-format", at: now)
        }
        try await history.recordVisit(url: URL(string: "https://swift.org")!, title: "Swift.org", at: now.addingTimeInterval(-200 * 86_400))
        try await history.recordVisit(url: URL(string: "https://example.com")!, title: "Example", at: now)

        let results = try await history.search("gith swi")
        #expect(results.map(\.url) == ["https://github.com/swiftlang/swift-format", "https://github.com/swiftlang/swift"])
        let swiftResults = try await history.search("swift")
        #expect(swiftResults.first?.visitCount == 5)
        #expect(swiftResults.last?.url == "https://swift.org")
    }

    @Test func revisitUpdatesCountAndTitle() async throws {
        let history = HistoryStore(database: try .inMemory())
        let url = URL(string: "https://docs.rs/tokio")!
        try await history.recordVisit(url: url, title: "")
        try await history.recordVisit(url: url, title: "tokio - Rust", typed: true)
        let entry = try #require(try await history.search("tokio").first)
        #expect(entry.visitCount == 2)
        #expect(entry.typedCount == 1)
        #expect(entry.title == "tokio - Rust")
    }

    @Test func skipsNonWebSchemes() async throws {
        let history = HistoryStore(database: try .inMemory())
        try await history.recordVisit(url: URL(string: "about:blank")!, title: "blank")
        #expect(try await history.recent().isEmpty)
    }

    @Test func patternEscapesFTSSyntax() {
        #expect(HistoryStore.prefixPattern("a\"b OR c*") == "\"a\"* \"b\"* \"or\"* \"c\"*")
        #expect(HistoryStore.prefixPattern("  ") == nil)
    }
}

@MainActor
@Suite struct BookmarkTests {
    @Test func importKeepsTreeAndOrder() async throws {
        let library = BookmarkLibrary(database: try .inMemory())
        try await library.importTree([
            ImportedBookmark(title: "Docs", url: nil, children: [
                ImportedBookmark(title: "MDN", url: URL(string: "https://developer.mozilla.org")),
                ImportedBookmark(title: "Rust", url: URL(string: "https://doc.rust-lang.org")),
            ]),
            ImportedBookmark(title: "GitHub", url: URL(string: "https://github.com")),
        ])
        try await Task.sleep(for: .milliseconds(50))
        let bar = library.children(of: nil)
        #expect(bar.map(\.title) == ["Docs", "GitHub"])
        #expect(library.children(of: bar[0].id).map(\.title) == ["MDN", "Rust"])
    }

    @Test func moveReorders() async throws {
        let library = BookmarkLibrary(database: try .inMemory())
        let a = try await library.add(title: "A", url: URL(string: "https://a.com"))
        try await library.add(title: "B", url: URL(string: "https://b.com"))
        try await library.add(title: "C", url: URL(string: "https://c.com"))
        try await Task.sleep(for: .milliseconds(50))
        try await library.move(a, to: 2, in: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(library.children(of: nil).map(\.title) == ["B", "C", "A"])
    }

    @Test func moveIntoFolderAndRejectCycles() async throws {
        let library = BookmarkLibrary(database: try .inMemory())
        let outer = try await library.add(title: "Outer", url: nil)
        let inner = try await library.add(title: "Inner", url: nil)
        let page = try await library.add(title: "A", url: URL(string: "https://a.com"))
        try await Task.sleep(for: .milliseconds(50))
        try await library.move(inner, to: 0, in: outer.id)
        try await library.move(page, to: 0, in: inner.id)
        try await Task.sleep(for: .milliseconds(50))
        #expect(library.children(of: nil).map(\.title) == ["Outer"])
        #expect(library.children(of: inner.id).map(\.title) == ["A"])
        await #expect(throws: BookmarkLibrary.Failure.folderIntoItself) { try await library.move(outer, to: 0, in: outer.id) }
        await #expect(throws: BookmarkLibrary.Failure.folderIntoItself) { try await library.move(outer, to: 0, in: inner.id) }
        #expect(!library.canMove(outer, into: outer.id))
        #expect(!library.canMove(outer, into: inner.id))
        #expect(library.canMove(inner, into: nil))
        #expect(library.canMove(page, into: outer.id))
    }

    @Test func moveBeforeSibling() async throws {
        let library = BookmarkLibrary(database: try .inMemory())
        let a = try await library.add(title: "A", url: URL(string: "https://a.com"))
        let b = try await library.add(title: "B", url: URL(string: "https://b.com"))
        let c = try await library.add(title: "C", url: URL(string: "https://c.com"))
        try await Task.sleep(for: .milliseconds(50))
        try await library.move(c, before: a, in: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(library.children(of: nil).map(\.title) == ["C", "A", "B"])
        try await library.move(library.children(of: nil)[0], before: nil, in: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(library.children(of: nil).map(\.title) == ["A", "B", "C"])
        try await library.move(b, before: b, in: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(library.children(of: nil).map(\.title) == ["A", "B", "C"])
    }

    @Test func renameKeepsLaterMove() async throws {
        let library = BookmarkLibrary(database: try .inMemory())
        let folder = try await library.add(title: "Folder", url: nil)
        let page = try await library.add(title: "A", url: URL(string: "https://a.com"))
        try await Task.sleep(for: .milliseconds(50))
        try await library.move(page, to: 0, in: folder.id)
        try await library.rename(page, to: "Renamed")
        try await Task.sleep(for: .milliseconds(50))
        #expect(library.children(of: folder.id).map(\.title) == ["Renamed"])
    }
}

@Suite struct SessionTests {
    @Test func roundTrips() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("session-\(UUID()).json")
        let store = SessionStore(fileURL: url)
        let tab = TabSnapshot(id: UUID(), url: URL(string: "https://github.com"), title: "GitHub",
                              isPinned: true, openerID: nil, interactionState: Data([1, 2, 3]))
        let session = Session(windows: [WindowSnapshot(frame: CGRect(x: 1, y: 2, width: 3, height: 4), tabs: [tab], selectedIndex: 0)],
                              recentlyClosed: [.tab(tab, index: 2)])
        store.save(session, sync: true)
        #expect(store.load() == session)
    }
}

@Suite struct FaviconStoreTests {
    @Test func skipsCandidatesThatDontDecode() async throws {
        let store = FaviconStore(database: try .inMemory())
        let html = try #require(URL(string: "data:text/html;base64," + Data("<html>Sign in</html>".utf8).base64EncodedString()))
        let png = try #require(URL(string: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="))
        let data = await store.icon(host: "example.com", candidates: [html, png])
        #expect(data?.count == 70)
        #expect(await store.cached(host: "example.com") == data)
    }
}

@Suite struct FaviconRankingTests {
    @Test func prefersSVGThenSmallestAtLeast32() {
        let page = URL(string: "https://example.com/a/b")!
        let links: [FaviconCandidates.Link] = [
            .init(href: "https://example.com/16.png", rel: "icon", sizes: "16x16", type: "image/png"),
            .init(href: "https://example.com/64.png", rel: "icon", sizes: "64x64", type: "image/png"),
            .init(href: "https://example.com/32.png", rel: "icon", sizes: "32x32", type: "image/png"),
            .init(href: "https://example.com/mask.svg", rel: "mask-icon", sizes: "", type: ""),
            .init(href: "https://example.com/icon.svg", rel: "icon", sizes: "", type: "image/svg+xml"),
        ]
        let ranked = FaviconCandidates.rank(links, pageURL: page).map(\.lastPathComponent)
        #expect(ranked == ["icon.svg", "32.png", "64.png", "16.png", "favicon.ico"])
    }

    @Test func reencodesDataHrefsAsBase64() throws {
        let page = URL(string: "https://example.com/")!
        // As WebKit serializes it: raw spaces beside percent-escapes.
        let svg = "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg'%3E%3C/svg%3E"
        let png = "data:image/png;base64,iVBORw0KGgo="
        let ranked = FaviconCandidates.rank([
            .init(href: png, rel: "icon", sizes: "32x32", type: ""),
            .init(href: svg, rel: "icon", sizes: "", type: ""),
        ], pageURL: page)
        #expect(ranked.count == 3)
        #expect(ranked[0].absoluteString.hasPrefix("data:image/svg+xml;base64,"))
        let payload = try #require(ranked[0].absoluteString.split(separator: ",").last)
        #expect(Data(base64Encoded: String(payload)) == Data("<svg xmlns='http://www.w3.org/2000/svg'></svg>".utf8))
        #expect(ranked[1].absoluteString == png)
        #expect(ranked[2].lastPathComponent == "favicon.ico")
    }
}
