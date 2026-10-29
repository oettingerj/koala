import Foundation
import GRDB

public struct Suggestion: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        case navigate, search, keyword, tab, command, bookmark, history, web, github, closed
    }

    /// Where a row sits in the list. Local sections sort before remote ones, so rows that
    /// stream in afterwards land below everything already shown.
    public enum Section: Int, Sendable, Equatable, Comparable {
        case top, tabs, bookmarks, commands, github, history, suggestions
        case reviewQueue, recentlyClosed, frequent

        public var title: String? {
            switch self {
            case .top: nil
            case .tabs: "Tabs"
            case .bookmarks: "Bookmarks"
            case .commands: "Commands"
            case .github: "GitHub"
            case .history: "History"
            case .suggestions: "Suggestions"
            case .reviewQueue: "Review Queue"
            case .recentlyClosed: "Recently Closed"
            case .frequent: "Frequent"
            }
        }

        public static func < (a: Section, b: Section) -> Bool { a.rawValue < b.rawValue }

        static func `default`(for kind: Kind) -> Section {
            switch kind {
            case .navigate, .search, .keyword: .top
            case .tab: .tabs
            case .command: .commands
            case .bookmark: .bookmarks
            case .history: .history
            case .web: .suggestions
            case .github: .github
            case .closed: .recentlyClosed
            }
        }
    }

    public enum Action: Equatable, Sendable {
        case open(URL)
        case switchToTab(UUID)
        /// An Objective-C selector name sent through the responder chain.
        case command(String)
        /// An index into the app's recently closed list.
        case reopenClosed(Int)
    }

    public var id: String
    public var kind: Kind
    public var section: Section
    public var title: String
    public var subtitle: String?
    public var action: Action
    public var score: Double
    /// Host whose favicon represents the row.
    public var iconHost: String?
    /// Key equivalent shown beside commands.
    public var shortcut: String?
    /// The menus a command lives in ("View ▸ Developer").
    public var menuPath: String?
    /// The completion the field shows ahead of the caret, on the row it opens.
    public var inline: InlineCompletion?
    /// Visit facts carried by history rows.
    public var visitCount: Int?
    public var lastVisitedAt: Date?

    public init(id: String, kind: Kind, section: Section? = nil, title: String, subtitle: String? = nil, action: Action,
                score: Double, iconHost: String? = nil, shortcut: String? = nil) {
        self.id = id
        self.kind = kind
        self.section = section ?? .default(for: kind)
        self.title = title
        self.subtitle = subtitle
        self.action = action
        self.score = score
        self.iconHost = iconHost
        self.shortcut = shortcut
    }
}

/// Builds command bar and address field suggestions. Local sources answer synchronously on
/// every keystroke; history full-text search and web suggestions arrive afterwards.
@MainActor
public final class SuggestionEngine {
    public struct TabInfo: Sendable {
        public var id: UUID
        public var title: String
        public var url: URL?
        public init(id: UUID, title: String, url: URL?) { self.id = id; self.title = title; self.url = url }
    }

    public struct CommandInfo: Sendable {
        public var selector: String
        public var title: String
        public var shortcut: String?
        public var menuPath: String?
        public init(selector: String, title: String, shortcut: String?, menuPath: String? = nil) {
            self.selector = selector; self.title = title; self.shortcut = shortcut; self.menuPath = menuPath
        }
    }

    public var tabs: () -> [TabInfo] = { [] }
    public var commands: () -> [CommandInfo] = { [] }
    public var keywordSearches = KeywordSearch.defaults
    public var searchTemplate = AddressInput.defaultSearchTemplate
    /// The engine `searchTemplate` belongs to, as search rows name it ("Search Kagi").
    public var searchName = "Google"
    public var webSuggestionsEnabled = true
    /// Extra asynchronous rows from the app (GitHub review queue and repository search).
    public var extraRemote: (@MainActor (String) async -> [Suggestion])?
    /// Rows the app shows for an empty query (review queue, recently closed).
    public var zeroState: () -> [Suggestion] = { [] }

    private let bookmarks: BookmarkLibrary?
    private let history: HistoryStore?
    private let database: AppDatabase?
    /// Where web suggestions come from; follows the chosen search engine.
    public var web: WebSuggestions
    /// Hosts the user visits, by frecency, so "gith⏎" goes to github.com without a database hit.
    private(set) var knownHosts: [(host: String, weight: Double, visits: Int, lastVisit: Date?)] = []
    /// Visited addresses for inline completion, kept in memory so completing costs no database read.
    var completionIndex = CompletionIndex()

    public init(bookmarks: BookmarkLibrary?, history: HistoryStore?, database: AppDatabase?, web: WebSuggestions = WebSuggestions()) {
        self.bookmarks = bookmarks
        self.history = history
        self.database = database
        self.web = web
    }

    /// Refreshes the in-memory host and address indexes. Cheap; call at launch and after imports.
    public func reloadHostIndex() async {
        guard let database else { return }
        let rows = (try? await database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT host, SUM(visitCount + typedCount * 2) AS weight, SUM(visitCount) AS visits,
                       MAX(lastVisitedAt) AS last FROM history
                WHERE host != '' GROUP BY host ORDER BY weight DESC LIMIT 2000
                """).map { (host: $0["host"] as String, weight: Double($0["weight"] as Int),
                            visits: $0["visits"] as Int, lastVisit: $0["last"] as Date?) }
        }) ?? []
        knownHosts = rows
        let urls = (try? await database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT url, visitCount, typedCount, lastVisitedAt FROM history
                ORDER BY visitCount + typedCount * 2 DESC, lastVisitedAt DESC LIMIT 5000
                """).compactMap { row -> CompletionIndex.Entry? in
                    guard let url = URL(string: row["url"] as String) else { return nil }
                    return CompletionIndex.entry(url: url, visits: row["visitCount"], typed: row["typedCount"],
                                                 lastVisit: row["lastVisitedAt"])
                }
        }) ?? []
        completionIndex = CompletionIndex(urls)
    }

    /// Records a committed navigation in both indexes, so it completes without a reload.
    public func noteVisit(url: URL, typed: Bool) {
        guard let host = DisplayURL(url)?.host else { return }
        noteVisit(host: host)
        if typed, let index = knownHosts.firstIndex(where: { $0.host == host }) { knownHosts[index].weight += 2 }
        completionIndex.noteVisit(url: url, typed: typed, at: Date())
    }

    /// Seeds the address index directly, for tests.
    func loadCompletionIndex(_ visits: [(url: URL, visits: Int, typed: Int, lastVisit: Date?)]) {
        completionIndex = CompletionIndex(visits.compactMap { CompletionIndex.entry(url: $0.url, visits: $0.visits, typed: $0.typed, lastVisit: $0.lastVisit) })
        for visit in visits {
            guard let host = DisplayURL(visit.url)?.host else { continue }
            let weight = Double(visit.visits + visit.typed * 2)
            if let index = knownHosts.firstIndex(where: { $0.host == host }) {
                knownHosts[index].weight += weight
                knownHosts[index].visits += visit.visits
                knownHosts[index].lastVisit = [knownHosts[index].lastVisit, visit.lastVisit].compactMap { $0 }.max()
            } else {
                knownHosts.append((host, weight, visit.visits, visit.lastVisit))
            }
        }
    }

    /// Whether the user has visited `host`, so fetching its icon reveals nothing new.
    public func isKnownHost(_ host: String) -> Bool {
        knownHosts.contains { $0.host == host }
    }

    public func noteVisit(host: String) {
        if let index = knownHosts.firstIndex(where: { $0.host == host }) {
            knownHosts[index].weight += 1
            knownHosts[index].visits += 1
            knownHosts[index].lastVisit = Date()
        } else {
            knownHosts.append((host, 1, 1, Date()))
        }
    }

    // MARK: Local (synchronous)

    public func localResults(for raw: String, limit: Int = 8, completion: CompletionContext = .init()) -> [Suggestion] {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        var results: [Suggestion] = []
        results.append(contentsOf: primaryRows(for: raw, trimmed: text, completion: completion))
        guard KeywordSearch.match(raw, in: keywordSearches) == nil else { return results }

        var ranked: [Suggestion] = []
        let openTabs = tabs()
        let openURLs = Set(openTabs.compactMap { $0.url?.absoluteString })
        for tab in openTabs {
            let host = DisplayURL(tab.url)?.host ?? ""
            guard let score = best(FuzzyMatch.score(text, in: tab.title), FuzzyMatch.score(text, in: host)) else { continue }
            ranked.append(Suggestion(id: "tab:\(tab.id)", kind: .tab, title: tab.title.isEmpty ? host : tab.title,
                                     subtitle: tab.url?.absoluteString, action: .switchToTab(tab.id),
                                     score: score + 0.15, iconHost: host))
        }
        if text.count >= 2 {
            for command in commands() {
                // Commands need a real word match; subsequences ("gi" in "Origin") are noise here.
                guard let score = FuzzyMatch.score(text, in: command.title), score >= Self.minimumScore else { continue }
                var row = Suggestion(id: "cmd:\(command.selector):\(command.title)", kind: .command, title: command.title,
                                     action: .command(command.selector), score: score, shortcut: command.shortcut)
                row.menuPath = command.menuPath
                ranked.append(row)
            }
        }
        for bookmark in bookmarks?.all ?? [] {
            guard let urlString = bookmark.url, !openURLs.contains(urlString), let url = URL(string: urlString) else { continue }
            let host = DisplayURL(url)?.host ?? ""
            guard let score = best(FuzzyMatch.score(text, in: bookmark.title), FuzzyMatch.score(text, in: host)) else { continue }
            ranked.append(Suggestion(id: "url:\(urlString)", kind: .bookmark, title: bookmark.title,
                                     subtitle: urlString, action: .open(url), score: score + 0.1, iconHost: host))
        }
        ranked.sort { $0.score > $1.score }
        var rest = ranked.filter { row in !results.contains { $0.id == row.id } }
        // The strongest match joins the top hit, so grouping by section never buries it.
        if var top = rest.first, (FuzzyMatch.score(text, in: top.title) ?? 0) >= Self.topHitScore {
            top.section = .top
            results.append(top)
            rest.removeFirst()
        }
        var seen = Set(results.map(\.id))
        let kept = rest.filter { seen.insert($0.id).inserted }.prefix(max(0, limit - results.count))
        return results + kept.sorted { $0.section != $1.section ? $0.section < $1.section : $0.score > $1.score }
    }

    /// A title score only a whole-title prefix match reaches (prefix scores lose at most 0.15).
    static let topHitScore = 0.85

    /// Where `url` is bookmarked ("Bookmarks Bar ▸ Work"), or nil when it isn't.
    public func bookmarkFolderPath(for url: URL) -> String? {
        guard let library = bookmarks, let bookmark = library.all.first(where: { $0.url == url.absoluteString }) else { return nil }
        var names: [String] = []
        var parent = bookmark.parentID
        while let id = parent, let folder = library.all.first(where: { $0.id == id }), names.count < 8 {
            names.insert(folder.title, at: 0)
            parent = folder.parentID
        }
        return (["Bookmarks Bar"] + names).joined(separator: " ▸ ")
    }

    // MARK: Zero state

    /// Rows for an empty query: the app's rows, then the most visited hosts.
    public func zeroStateResults() -> [Suggestion] {
        let frequent = knownHosts.prefix(5).compactMap { entry -> Suggestion? in
            // Hosts with a port are local dev servers, which rarely speak TLS.
            guard let url = URL(string: "\(entry.host.contains(":") ? "http" : "https")://\(entry.host)") else { return nil }
            var row = Suggestion(id: "url:\(url.absoluteString)", kind: .navigate, section: .frequent, title: entry.host,
                                 action: .open(url), score: entry.weight, iconHost: entry.host)
            // Visits across the whole host, which is what ranks it here.
            row.visitCount = entry.visits
            row.lastVisitedAt = entry.lastVisit
            return row
        }
        var seen = Set<String>()
        return (zeroState() + frequent).filter { seen.insert($0.id).inserted }
    }

    private func primaryRows(for raw: String, trimmed text: String, completion: CompletionContext) -> [Suggestion] {
        if let (search, query) = KeywordSearch.match(raw, in: keywordSearches) {
            guard !query.isEmpty, let url = search.url(for: query) else { return [] }
            return [Suggestion(id: "kw:\(search.keyword)", kind: .keyword, title: query,
                               subtitle: "Search \(search.name)", action: .open(url), score: 10,
                               iconHost: DisplayURL(url)?.host)]
        }

        var rows: [Suggestion] = []
        // The likely address leads, selected, and fills the field ahead of the caret.
        if let (inline, url) = inlineCompletion(for: raw, context: completion) {
            let display = DisplayURL(url).map { $0.host + $0.remainder } ?? url.absoluteString
            var row = Suggestion(id: "url:\(url.absoluteString)", kind: .navigate, title: display, subtitle: "Open",
                                 action: .open(url), score: 12, iconHost: DisplayURL(url)?.host)
            row.inline = inline
            row.visitCount = inline.hostVisits
            row.lastVisitedAt = inline.hostLastVisit
            rows.append(row)
        }
        if let url = GitHubURL.shorthand(text) {
            rows.append(Suggestion(id: "url:\(url.absoluteString)", kind: .github, section: .top, title: text,
                                   subtitle: "Open on GitHub", action: .open(url), score: 11, iconHost: "github.com"))
        }
        let resolved = AddressInput.resolve(text, searchTemplate: searchTemplate)
        let isSearch = resolved.map { AddressInput.searchURL(for: text, template: searchTemplate) == $0 } ?? true

        let completed = rows.first?.inline != nil
        if let resolved {
            if isSearch {
                rows.append(Suggestion(id: "search:\(text)", kind: .search, title: text, subtitle: "Search \(searchName)",
                                       action: .open(resolved), score: 9))
            } else {
                rows.insert(Suggestion(id: "url:\(resolved.absoluteString)", kind: .navigate,
                                       title: DisplayURL(resolved).map { $0.host + $0.remainder } ?? resolved.absoluteString,
                                       subtitle: "Open", action: .open(resolved), score: 10,
                                       iconHost: DisplayURL(resolved)?.host), at: completed ? 1 : 0)
            }
        }
        // A known host the completion didn't claim (rejected, or too close to call) is still
        // offered, below the search, so Return does what the field says.
        if !completed, isSearch, !text.contains(" "), let host = completedHost(for: text) {
            let url = URL(string: "https://\(host)")!
            rows.append(Suggestion(id: "url:\(url.absoluteString)", kind: .navigate, title: host,
                                   subtitle: "Open", action: .open(url), score: 10, iconHost: host))
        }
        var seen = Set<String>()
        return rows.filter { seen.insert($0.id).inserted }
    }

    /// The most-visited known host starting with `prefix` (ignoring "www."), when the prefix
    /// is long enough to be deliberate.
    func completedHost(for prefix: String) -> String? {
        let p = prefix.lowercased()
        guard p.count >= 2, p.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return knownHosts.first { $0.host.hasPrefix(p) && $0.weight >= 2 }?.host
    }

    static func withoutFragment(_ url: URL) -> String {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.string ?? url.absoluteString
    }

    /// Best score across fields, ignoring loose subsequence matches that read as noise in a list.
    private func best(_ scores: Double?...) -> Double? {
        scores.compactMap { $0 }.filter { $0 >= Self.minimumScore }.max()
    }

    static let minimumScore = 0.5

    // MARK: Remote (asynchronous)

    /// History matches and web suggestions; rows already present locally are dropped by the caller.
    public func remoteResults(for raw: String) async -> [Suggestion] {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, KeywordSearch.match(raw, in: keywordSearches) == nil else { return [] }
        async let historyRows = historyResults(for: text)
        async let webRows = webResults(for: text)
        let extra = await extraRemote?(text) ?? []
        return await extra + historyRows + webRows
    }

    private func historyResults(for text: String) async -> [Suggestion] {
        guard let history, let entries = try? await history.search(text, limit: 6) else { return [] }
        // Pages differing only by fragment (#L5-L9) are one page in a list of suggestions.
        var seen = Set(tabs().compactMap { $0.url.map(Self.withoutFragment) })
        return entries.compactMap { entry in
            guard let url = URL(string: entry.url), seen.insert(Self.withoutFragment(url)).inserted else { return nil }
            let fallback = DisplayURL(url).map { $0.host + $0.remainder } ?? entry.url
            var row = Suggestion(id: "url:\(entry.url)", kind: .history, title: entry.title.isEmpty ? fallback : entry.title,
                                 subtitle: entry.url, action: .open(url), score: 0, iconHost: entry.host)
            row.visitCount = entry.visitCount
            row.lastVisitedAt = entry.lastVisitedAt
            return row
        }
    }

    private func webResults(for text: String) async -> [Suggestion] {
        let template = searchTemplate, name = searchName
        guard webSuggestionsEnabled, web.endpoint != nil,
              AddressInput.resolve(text, searchTemplate: template).map({ AddressInput.searchURL(for: text, template: template) == $0 }) ?? false
        else { return [] }
        let phrases = await web.suggestions(for: text)
        return phrases.prefix(4).compactMap { phrase in
            guard phrase.lowercased() != text.lowercased(), let url = AddressInput.searchURL(for: phrase, template: template) else { return nil }
            return Suggestion(id: "search:\(phrase)", kind: .web, title: phrase, subtitle: "Search \(name)", action: .open(url), score: 0)
        }
    }
}

/// Search-as-you-type phrases from the search provider. Cancelled per keystroke by the caller.
public struct WebSuggestions: Sendable {
    public static let google = "https://suggestqueries.google.com/complete/search?client=firefox&q=%s"

    /// The chosen engine's suggestion URL with `%s` for the query; nil when it offers none,
    /// so nothing typed leaves the browser.
    public var endpoint: String?

    public init(endpoint: String? = WebSuggestions.google) {
        self.endpoint = endpoint
    }

    public func suggestions(for query: String) async -> [String] {
        guard let endpoint, let url = AddressInput.searchURL(for: query, template: endpoint) else { return [] }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 2)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return [] }
        return Self.phrases(from: data)
    }

    /// Phrases from an OpenSearch suggestion response (`["query", ["phrase", …]]`, as Google,
    /// Bing, and DuckDuckGo's list type send) or DuckDuckGo's `[{"phrase": …}]`.
    static func phrases(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return [] }
        if json.count > 1, let phrases = json[1] as? [String] { return phrases }
        return json.compactMap { ($0 as? [String: Any])?["phrase"] as? String }
    }
}
