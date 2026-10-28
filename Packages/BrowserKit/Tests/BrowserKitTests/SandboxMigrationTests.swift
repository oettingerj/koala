import Foundation
import Testing
@testable import BrowserKit

@Suite struct SandboxMigrationTests {
    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    private func read(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
    }

    @Test func copiesContainerDataWithoutOverwriting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID())")
        let container = root.appendingPathComponent("Containers/app/Data/Library"), library = root.appendingPathComponent("Library")
        try write("db", to: container.appendingPathComponent("Application Support/Koala/koala.sqlite"))
        try write("site", to: container.appendingPathComponent("WebKit/WebsiteData/LocalStorage/x"))
        try write("cookies", to: container.appendingPathComponent("Cookies/Cookies.binarycookies"))
        // Already outside the container: left alone.
        try write("newer", to: library.appendingPathComponent("HTTPStorages/app/httpstorages.sqlite"))
        try write("older", to: container.appendingPathComponent("HTTPStorages/app/httpstorages.sqlite"))

        let migration = SandboxMigration(container: container, library: library, bundleID: "app", supportFolder: "Koala Dev")
        #expect(migration.copy().isEmpty)
        #expect(read(library.appendingPathComponent("Application Support/Koala Dev/koala.sqlite")) == "db")
        #expect(read(library.appendingPathComponent("WebKit/app/WebsiteData/LocalStorage/x")) == "site")
        #expect(read(library.appendingPathComponent("Cookies/app.binarycookies")) == "cookies")
        #expect(read(library.appendingPathComponent("HTTPStorages/app/httpstorages.sqlite")) == "newer")
        // The container stays as it was.
        #expect(read(container.appendingPathComponent("Application Support/Koala/koala.sqlite")) == "db")
        #expect(!FileManager.default.fileExists(atPath: library.appendingPathComponent("Application Support/.Koala Dev.copying").path))
    }

    @Test func noContainerIsNothingToDo() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID())")
        let migration = SandboxMigration(container: root.appendingPathComponent("missing"), library: root, bundleID: "app", supportFolder: "Koala")
        #expect(migration.copy().isEmpty)
    }
}
