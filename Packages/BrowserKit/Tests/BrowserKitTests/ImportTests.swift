import Foundation
import GRDB
import Testing
@testable import BrowserKit

@Suite struct DownloadNamingTests {
    @Test(arguments: [
        ("report.pdf", "report.pdf"),
        ("../../etc/passwd", "-..-etc-passwd"),
        ("..hidden", "hidden"),
        ("a/b\\c:d.txt", "a-b-c-d.txt"),
        ("  spaced  ", "spaced"),
        ("", "download"),
        (nil as String?, "download"),
        ("line\nbreak.zip", "line-break.zip"),
    ])
    func sanitizes(input: String?, expected: String) {
        #expect(DownloadNaming.sanitize(input) == expected)
    }

    @Test func shortensKeepingExtension() {
        let long = String(repeating: "a", count: 400) + ".tar.gz"
        let name = DownloadNaming.sanitize(long)
        #expect(name.utf8.count <= 200)
        #expect(name.hasSuffix(".gz"))
    }

    @Test func uniqueNamesCount() {
        let dir = URL(fileURLWithPath: "/tmp/dl")
        let taken: Set<String> = ["/tmp/dl/file.zip", "/tmp/dl/file 2.zip"]
        #expect(DownloadNaming.uniqueURL(for: "file.zip", in: dir) { taken.contains($0.path) }.lastPathComponent == "file 3.zip")
        #expect(DownloadNaming.uniqueURL(for: "new.zip", in: dir) { taken.contains($0.path) }.lastPathComponent == "new.zip")
    }
}

@Suite struct BookmarkImporterTests {
    @Test func chromeBarItemsLandOnBarAndOtherBecomesFolder() throws {
        let json = """
        {"roots": {
          "bookmark_bar": {"name": "Bookmarks bar", "type": "folder", "children": [
            {"name": "GitHub", "type": "url", "url": "https://github.com", "date_added": "13300000000000000"},
            {"name": "Docs", "type": "folder", "children": [
              {"name": "MDN", "type": "url", "url": "https://developer.mozilla.org"},
              {"name": "Script", "type": "url", "url": "javascript:alert(1)"}]}]},
          "other": {"name": "Other bookmarks", "type": "folder", "children": [
            {"name": "HN", "type": "url", "url": "https://news.ycombinator.com"}]},
          "synced": {"name": "Mobile", "type": "folder", "children": []}}}
        """
        let items = try BookmarkImporters.bookmarks(from: Data(json.utf8))
        #expect(items.map(\.title) == ["GitHub", "Docs", "Other bookmarks"])
        #expect(items[1].children.map(\.title) == ["MDN"])
        #expect(items[0].createdAt != nil)
    }

    @Test func braveBookmarksWithSyncMetadata() throws {
        // Brave writes Chromium's format plus checksum, version and sync fields.
        let json = """
        {"checksum": "abc", "version": 1, "sync_metadata": "Cg==",
         "roots": {
          "bookmark_bar": {"name": "Bookmarks", "type": "folder", "meta_info": {"order": "1.0"}, "children": [
            {"name": "Brave Search", "type": "url", "url": "https://search.brave.com", "guid": "x"}]},
          "other": {"name": "Other Bookmarks", "type": "folder", "children": []},
          "synced": {"name": "Mobile Bookmarks", "type": "folder", "children": [
            {"name": "Rewards", "type": "url", "url": "brave://rewards"}]}}}
        """
        let items = try BookmarkImporters.bookmarks(from: Data(json.utf8))
        #expect(items.map(\.title) == ["Brave Search"])
    }

    @Test func netscapeHTMLFromSafari() throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <HTML><TITLE>Bookmarks</TITLE><H1>Bookmarks</H1>
        <DL><p>
          <DT><H3 FOLDED>Favorites</H3>
          <DL><p>
            <DT><A HREF="https://github.com/">GitHub</A>
            <DT><H3>Rust</H3>
            <DL><p>
              <DT><A HREF="https://docs.rs/" ADD_DATE="1700000000">Docs &amp; crates</A>
            </DL><p>
          </DL><p>
        </DL><p>
        """
        let items = try BookmarkImporters.bookmarks(from: Data(html.utf8))
        #expect(items.map(\.title) == ["GitHub", "Rust"])
        #expect(items[1].children.first?.title == "Docs & crates")
        #expect(items[1].children.first?.createdAt == Date(timeIntervalSince1970: 1_700_000_000))
    }

    @Test func arcSidebar() throws {
        let json = """
        {"sidebar": {"containers": [{"global": {}}, {"items": [
          "space", {"id": "space", "title": "Work", "childrenIds": ["list", "tab1"], "data": {"itemContainer": {}}},
          "list", {"id": "list", "parentID": "space", "title": "Repos", "childrenIds": ["tab2"], "data": {"list": {}}},
          "tab1", {"id": "tab1", "parentID": "space", "title": null, "childrenIds": [],
                   "data": {"tab": {"savedURL": "https://linear.app", "savedTitle": "Linear"}}},
          "tab2", {"id": "tab2", "parentID": "list", "title": "Koala", "childrenIds": [],
                   "data": {"tab": {"savedURL": "https://github.com/josh/koala", "savedTitle": "x"}}}
        ]}]}}
        """
        let items = try BookmarkImporters.bookmarks(from: Data(json.utf8))
        let arc = try #require(items.first)
        #expect(arc.title == "Arc")
        let work = try #require(arc.children.first)
        #expect(work.title == "Work")
        #expect(work.children.map(\.title) == ["Repos", "Linear"])
        #expect(work.children[0].children.first?.url?.absoluteString == "https://github.com/josh/koala")
    }

    @Test func rejectsUnknownFiles() {
        #expect(throws: BookmarkImporters.Failure.unrecognized) { try BookmarkImporters.bookmarks(from: Data("hello".utf8)) }
    }
}

@Suite struct ChromeHistoryImportTests {
    private func makeHistory(at file: URL) async throws {
        let chrome = try DatabaseQueue(path: file.path)
        try await chrome.write { db in
            try db.execute(sql: """
                CREATE TABLE urls (id INTEGER PRIMARY KEY, url TEXT, title TEXT, visit_count INTEGER,
                  typed_count INTEGER, last_visit_time INTEGER, hidden INTEGER DEFAULT 0);
                INSERT INTO urls (url, title, visit_count, typed_count, last_visit_time) VALUES
                  ('https://github.com/', 'GitHub', 40, 10, 13350000000000000),
                  ('chrome://settings', 'Settings', 3, 0, 13350000000000000);
                """)
        }
    }

    @Test func readsAndMergesVisits() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("History-\(UUID())")
        try await makeHistory(at: file)
        let entries = try ChromeHistoryImporter.entries(fromDatabaseAt: file)
        #expect(entries.map(\.url) == ["https://github.com/"])
        let history = HistoryStore(database: try .inMemory())
        try await history.recordVisit(url: URL(string: "https://github.com/")!, title: "")
        try await history.importEntries(entries)
        let merged = try #require(try await history.search("github").first)
        #expect(merged.visitCount == 41)
        #expect(merged.title == "GitHub")
    }

    @Test func profileFolderYieldsBookmarksAndHistory() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Profile-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try await makeHistory(at: folder.appendingPathComponent("History"))
        try Data("""
            {"roots": {"bookmark_bar": {"name": "Bookmarks", "type": "folder", "children": [
              {"name": "Brave Search", "type": "url", "url": "https://search.brave.com"}]}}}
            """.utf8).write(to: folder.appendingPathComponent("Bookmarks"))
        let contents = try ChromiumProfileImporter.contents(ofProfileAt: folder)
        #expect(contents.bookmarks.map(\.title) == ["Brave Search"])
        #expect(contents.history.map(\.url) == ["https://github.com/"])
    }

    @Test func rejectsFolderWithoutProfileFiles() {
        #expect(throws: BookmarkImporters.Failure.unrecognized) {
            try ChromiumProfileImporter.contents(ofProfileAt: FileManager.default.temporaryDirectory)
        }
    }
}
