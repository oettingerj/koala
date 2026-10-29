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

    @Test func searchRowNamesTheChosenEngine() {
        let e = engine()
        e.searchTemplate = "https://kagi.com/search?q=%s"
        e.searchName = "Kagi"
        let row = e.localResults(for: "swift actors").first
        #expect(row?.subtitle == "Search Kagi")
        #expect(row?.action == .open(URL(string: "https://kagi.com/search?q=swift%20actors")!))
    }

    @Test func parsesOpenSearchAndDuckDuckGoSuggestions() {
        #expect(WebSuggestions.phrases(from: Data(#"["swi",["swift","swiftui"]]"#.utf8)) == ["swift", "swiftui"])
        #expect(WebSuggestions.phrases(from: Data(#"[{"phrase":"swift"},{"phrase":"swiftui"}]"#.utf8)) == ["swift", "swiftui"])
        #expect(WebSuggestions.phrases(from: Data("<html>".utf8)).isEmpty)
    }

    @Test func noEndpointSendsNothing() async {
        let e = SuggestionEngine(bookmarks: nil, history: nil, database: nil, web: WebSuggestions(endpoint: nil))
        #expect(await e.remoteResults(for: "swift actors").isEmpty)
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

    @Test func localRowsComeInSectionOrder() {
        let tabs = (0..<3).map { SuggestionEngine.TabInfo(id: UUID(), title: "Show tab \($0)", url: URL(string: "https://site\($0).com")) }
        let rows = engine(tabs: tabs).localResults(for: "show")
        let sections = rows.map(\.section)
        #expect(sections == sections.sorted())
        #expect(sections.contains(.tabs) && sections.contains(.commands))
    }

    @Test func strongestMatchJoinsTopHit() throws {
        let id = UUID()
        let rows = engine(tabs: [.init(id: id, title: "Swift Forums", url: URL(string: "https://forums.swift.org"))])
            .localResults(for: "swift")
        #expect(rows.first?.kind == .search)
        let tab = try #require(rows.first { $0.action == .switchToTab(id) })
        #expect(tab.section == .top)
        // A weak match stays in its own section.
        let weak = engine(tabs: [.init(id: id, title: "About Swift", url: nil)]).localResults(for: "swift")
        #expect(weak.first { $0.action == .switchToTab(id) }?.section == .tabs)
        // A host match alone isn't a top hit, however strong.
        let host = engine(tabs: [.init(id: id, title: "[Runtime] Allow", url: URL(string: "https://github.com/a/b/pull/1"))])
            .localResults(for: "git")
        #expect(host.first { $0.action == .switchToTab(id) }?.section == .tabs)
    }

    @Test func keywordIconHostDropsWWW() {
        let e = engine()
        e.keywordSearches = [KeywordSearch(keyword: "g", name: "Google", template: "https://www.google.com/search?q=%s")]
        #expect(e.localResults(for: "g swift").first?.iconHost == "google.com")
    }

    @Test func zeroStateCombinesAppRowsAndFrequentHosts() {
        let e = engine()
        #expect(e.zeroStateResults().isEmpty)
        e.noteVisit(host: "github.com")
        let closed = Suggestion(id: "closed:1", kind: .closed, title: "Closed", action: .reopenClosed(0), score: 0)
        e.zeroState = { [closed] }
        let rows = e.zeroStateResults()
        #expect(rows.map(\.section) == [.recentlyClosed, .frequent])
        #expect(rows.last?.title == "github.com")
    }

    @Test func remoteSectionsSortAfterLocal() {
        let local: [Suggestion.Section] = [.top, .tabs, .bookmarks, .commands]
        let remote: [Suggestion.Section] = [.github, .history, .suggestions]
        #expect(local.allSatisfy { l in remote.allSatisfy { l < $0 } })
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

@MainActor
@Suite struct InlineCompletionTests {
    private let now = Date()

    private func engine(_ visits: [(String, Int, Int, Double)]) -> SuggestionEngine {
        let engine = SuggestionEngine(bookmarks: nil, history: nil, database: nil)
        engine.loadCompletionIndex(visits.map { (URL(string: $0.0)!, $0.1, $0.2, now.addingTimeInterval(-$0.3 * 86_400)) })
        return engine
    }

    private func completion(_ e: SuggestionEngine, _ text: String, _ context: CompletionContext = .init()) -> String? {
        e.inlineCompletion(for: text, context: context, now: now)?.0.text
    }

    @Test func completesHostBeforeSlash() {
        let e = engine([("https://github.com/swiftlang/swift", 5, 1, 0)])
        #expect(completion(e, "gith") == "github.com")
        #expect(completion(e, "GitH") == "GitHub.com".prefix(4) + "ub.com")
        #expect(completion(e, "https://www.gith") == "https://www.github.com")
    }

    @Test func completesAddressAfterSlash() throws {
        let e = engine([("https://github.com/swiftlang/swift", 5, 1, 0), ("https://github.com/settings", 1, 0, 0)])
        #expect(completion(e, "github.com/sw") == "github.com/swiftlang/swift")
        let (_, url) = try #require(e.inlineCompletion(for: "github.com/sw", now: now))
        #expect(url.absoluteString == "https://github.com/swiftlang/swift")
    }

    @Test func parentAbsorbsItsPages() {
        let e = engine([("https://github.com/swiftlang/swift", 1, 0, 0),
                        ("https://github.com/swiftlang/swift/pull/1", 3, 0, 0),
                        ("https://github.com/swiftlang/swift/pull/2", 3, 0, 0)])
        #expect(completion(e, "github.com/swi") == "github.com/swiftlang/swift")
        #expect(completion(e, "github.com/swiftlang/swift/p") == nil) // two pulls, too close to call
    }

    @Test func needsIntentAndAClearWinner() {
        // One incidental visit isn't intent.
        #expect(completion(engine([("https://docs.rs/serde/latest", 1, 0, 0)]), "docs.rs/se") == nil)
        // Two equally likely hosts: nothing is filled in.
        let tie = engine([("https://gitlab.com", 4, 0, 0), ("https://github.com", 4, 0, 0)])
        #expect(completion(tie, "git") == nil)
        #expect(completion(tie, "gith") == "github.com")
    }

    @Test func recencyDecays() {
        let e = engine([("https://gitlab.com", 6, 0, 120), ("https://github.com", 4, 0, 1)])
        #expect(completion(e, "git") == "github.com")
    }

    @Test func refusesNonAddressInput() {
        let e = engine([("https://github.com", 9, 3, 0), ("https://ghostty.org", 9, 3, 0)])
        #expect(completion(e, "g") == nil)
        #expect(completion(e, "gh") == nil) // the gh keyword, about to take a space
        #expect(completion(e, "github ") == nil)
        #expect(completion(e, "github.com") == nil) // nothing left to add
        #expect(completion(e, "gith", CompletionContext(enabled: false)) == nil)
    }

    @Test func rejectedCompletionStaysAway() {
        let e = engine([("https://github.com", 9, 3, 0)])
        #expect(completion(e, "gith", CompletionContext(suppressed: ["github.com"])) == nil)
        let rows = e.localResults(for: "gith", completion: CompletionContext(suppressed: ["github.com"]))
        #expect(rows.first?.kind == .search)
        #expect(rows.contains { $0.kind == .navigate && $0.title == "github.com" })
    }

    @Test func typingThroughKeepsTheShownCompletion() {
        let e = engine([("https://github.com", 4, 0, 0), ("https://gitlab.com", 4, 0, 0)])
        // Too close to call fresh, but already on screen: keep it.
        #expect(completion(e, "git", CompletionContext(current: "github.com")) == "github.com")
        #expect(completion(e, "gitl", CompletionContext(current: "github.com")) == "gitlab.com")
    }

    @Test func completionRowLeadsLocalResults() {
        let e = engine([("https://github.com/swiftlang/swift", 5, 2, 0)])
        let rows = e.localResults(for: "github.com/sw")
        #expect(rows.first?.inline?.text == "github.com/swiftlang/swift")
        #expect(rows.dropFirst().first?.title == "github.com/sw")
    }

    @Test func visitsUpdateTheIndex() {
        let e = engine([])
        let url = URL(string: "http://localhost:5173/dashboard")!
        e.noteVisit(url: url, typed: true)
        e.noteVisit(url: url, typed: false)
        #expect(completion(e, "localhost:5173/d") == "localhost:5173/dashboard")
        #expect(e.inlineCompletion(for: "localh", now: now)?.1.scheme == "http")
    }

    @Test func parentKeys() {
        #expect(SuggestionEngine.parentKeys(of: "a.com/x/y") == ["a.com/x/", "a.com/x", "a.com/", "a.com"])
    }
}
