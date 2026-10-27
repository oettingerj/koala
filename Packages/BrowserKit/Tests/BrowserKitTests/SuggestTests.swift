import Foundation
import Testing
@testable import BrowserKit

@Suite struct FuzzyMatchTests {
    @Test func ordersPrefixWordSubstringSubsequence() throws {
        let prefix = try #require(FuzzyMatch.score("git", in: "GitHub"))
        let word = try #require(FuzzyMatch.score("hub", in: "The Hub"))
        let substring = try #require(FuzzyMatch.score("thu", in: "GitHub"))
        let subsequence = try #require(FuzzyMatch.score("gtb", in: "GitHub"))
        #expect(prefix > word && word > substring && substring > subsequence)
    }

    @Test func tokensMatchWordPrefixes() {
        #expect(FuzzyMatch.score("swift form", in: "swift-format") != nil)
        #expect(FuzzyMatch.score("zzz", in: "GitHub") == nil)
    }
}

@Suite struct KeywordSearchTests {
    @Test func matchesKeywordAndSpace() throws {
        let (search, query) = try #require(KeywordSearch.match("mdn flex box", in: KeywordSearch.defaults))
        #expect(search.keyword == "mdn")
        #expect(query == "flex box")
        #expect(search.url(for: query)?.absoluteString == "https://developer.mozilla.org/en-US/search?q=flex%20box")
        #expect(KeywordSearch.match("mdnflex", in: KeywordSearch.defaults) == nil)
        #expect(KeywordSearch.match("unknown thing", in: KeywordSearch.defaults) == nil)
    }
}

@MainActor
@Suite struct SuggestionEngineTests {
    private func engine(tabs: [SuggestionEngine.TabInfo] = []) -> SuggestionEngine {
        let engine = SuggestionEngine(bookmarks: nil, history: nil, database: nil)
        engine.tabs = { tabs }
        engine.commands = {
            [.init(selector: "toggleBookmarksBar:", title: "Show Bookmarks Bar", shortcut: "⇧⌘B"),
             .init(selector: "reopenClosed:", title: "Reopen Closed Tab", shortcut: "⇧⌘T")]
        }
        return engine
    }

    @Test func urlInputLeadsWithNavigate() {
        let rows = engine().localResults(for: "github.com/apple")
        #expect(rows.first?.kind == .navigate)
        #expect(rows.first?.action == .open(URL(string: "https://github.com/apple")!))
    }

    @Test func textLeadsWithSearch() {
        let rows = engine().localResults(for: "swift actors")
        #expect(rows.first?.kind == .search)
    }

    @Test func keywordProducesOnlyKeywordRow() {
        let rows = engine().localResults(for: "crates serde")
        #expect(rows.count == 1)
        #expect(rows.first?.kind == .keyword)
        #expect(rows.first?.subtitle == "Search crates.io")
    }

    @Test func githubShorthandLeads() {
        let rows = engine().localResults(for: "swiftlang/swift#42")
        #expect(rows.first?.kind == .github)
        #expect(rows.first?.action == .open(URL(string: "https://github.com/swiftlang/swift/pull/42")!))
    }

    @Test func knownHostCompletesBeforeSearch() {
        let e = engine()
        e.noteVisit(host: "github.com")
        e.noteVisit(host: "github.com")
        let rows = e.localResults(for: "gith")
        #expect(rows.map(\.kind) == [.navigate, .search])
        #expect(rows.first?.title == "github.com")
    }

    @Test func findsTabsAndCommands() {
        let id = UUID()
        let rows = engine(tabs: [.init(id: id, title: "Pull request #42", url: URL(string: "https://github.com/a/b/pull/42"))])
            .localResults(for: "pull")
        #expect(rows.contains { $0.action == .switchToTab(id) })
        let commandRows = engine().localResults(for: "reopen")
        #expect(commandRows.contains { $0.action == .command("reopenClosed:") && $0.shortcut == "⇧⌘T" })
    }

    @Test func localResultsStayUnderBudget() {
        let tabs = (0..<500).map { SuggestionEngine.TabInfo(id: UUID(), title: "Tab number \($0) about things", url: URL(string: "https://site\($0).com/path")) }
        let e = engine(tabs: tabs)
        for i in 0..<2000 { e.noteVisit(host: "host\(i).example.com") }
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            for query in ["t", "ta", "tab", "tab n", "tab nu", "site4", "abo"] { _ = e.localResults(for: query) }
        }
        // 7 keystrokes; the budget is 8ms each.
        #expect(elapsed < .milliseconds(56))
    }
}
