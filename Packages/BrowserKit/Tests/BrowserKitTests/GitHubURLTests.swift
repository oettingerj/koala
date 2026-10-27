import Foundation
import Testing
@testable import BrowserKit

@Suite struct GitHubURLTests {
    private func parse(_ string: String) -> GitHubURL? { GitHubURL(URL(string: string)) }

    @Test(arguments: [
        ("https://github.com/swiftlang/swift", GitHubURL.Kind.repository),
        ("https://github.com/swiftlang/swift/pull/80000", .pullRequest(number: 80000)),
        ("https://github.com/swiftlang/swift/pull/80000/files", .pullRequest(number: 80000)),
        ("https://github.com/swiftlang/swift/issues/12", .issue(number: 12)),
        ("https://github.com/swiftlang/swift/commit/abc123def", .commit(sha: "abc123def")),
        ("https://github.com/swiftlang/swift/blob/main/lib/AST/Decl.cpp#L10-L20",
         .blob(ref: "main", path: "lib/AST/Decl.cpp", lines: 10...20)),
        ("https://github.com/swiftlang/swift/blob/main/README.md#L5", .blob(ref: "main", path: "README.md", lines: 5...5)),
        ("https://github.com/swiftlang/swift/blob/main/README.md", .blob(ref: "main", path: "README.md", lines: nil)),
        ("https://github.com/swiftlang/swift/tree/main/stdlib", .tree(ref: "main", path: "stdlib")),
        ("https://github.com/swiftlang/swift/compare/main...feature/x", .compare(base: "main", head: "feature/x")),
        ("https://github.com/swiftlang/swift/actions/runs/123456", .actionsRun(id: 123456)),
        ("https://github.com/swiftlang/swift/releases", .other(path: "releases")),
        ("https://github.com/swiftlang/swift/issues", .other(path: "issues")),
    ])
    func parsesKinds(url: String, kind: GitHubURL.Kind) throws {
        let parsed = try #require(parse(url))
        #expect(parsed.owner == "swiftlang" && parsed.repo == "swift")
        #expect(parsed.kind == kind)
    }

    @Test(arguments: ["https://github.com", "https://github.com/settings/profile", "https://github.com/pulls",
                      "https://gitlab.com/a/b", "https://github.com/notifications", "https://github.com/swiftlang"])
    func ignoresNonRepositoryPages(url: String) {
        #expect(parse(url) == nil)
    }

    @Test func linesHandleColumnsAndReversal() {
        #expect(GitHubURL.lines("L20C3-L10C8") == 10...20)
        #expect(GitHubURL.lines("readme") == nil)
    }

    @Test func permalinkPinsSHAAndKeepsLines() throws {
        let parsed = try #require(parse("https://github.com/a/b/blob/main/Sources/My File.swift#L3-L9"))
        #expect(parsed.permalink(sha: "deadbeef")?.absoluteString == "https://github.com/a/b/blob/deadbeef/Sources/My%20File.swift#L3-L9")
    }

    @Test func labels() throws {
        #expect(try #require(parse("https://github.com/a/b/pull/7")).label == "a/b · #7")
        #expect(try #require(parse("https://github.com/a/b/blob/main/x/y.swift")).label == "a/b · y.swift")
    }

    @Test func shorthandJumps() {
        #expect(GitHubURL.shorthand("swiftlang/swift#42")?.absoluteString == "https://github.com/swiftlang/swift/pull/42")
        #expect(GitHubURL.shorthand("not a ref") == nil)
    }

    @Test func cleansPageTitles() {
        #expect(GitHubURL.itemTitle(fromPageTitle: "[Runtime] Allow ~Escapable types. by mikeash · Pull Request #80000 · swiftlang/swift")
                == "[Runtime] Allow ~Escapable types.")
        #expect(GitHubURL.itemTitle(fromPageTitle: "Crash on launch · Issue #12 · a/b") == "Crash on launch")
    }
}
