import Foundation
import GRDB

public struct Suggestion: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable, Equatable {
        case navigate, search, keyword, tab, command, bookmark, history, web, github
    }

    public enum Action: Equatable, Sendable {
        case open(URL)
        case switchToTab(UUID)
        /// An Objective-C selector name sent through the responder chain.
        case command(String)
    }

    public var id: String
    public var kind: Kind
    public var title: String
    public var subtitle: String?
    public var action: Action
    public var score: Double
    /// Host whose favicon represents the row.
    public var iconHost: String?
    /// Key equivalent shown beside commands.
    public var shortcut: String?

    public init(id: String, kind: Kind, title: String, subtitle: String? = nil, action: Action,
                score: Double, iconHost: String? = nil, shortcut: String? = nil) {
        self.id = id
        self.kind = kind
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
        public init(selector: String, title: String, shortcut: String?) {
            self.selector = selector; self.title = title; self.shortcut = shortcut
        }
    }

    public var tabs: () -> [TabInfo] = { [] }
    public var commands: () -> [CommandInfo] = { [] }
    public var keywordSearches = KeywordSearch.defaults
    public var searchTemplate = AddressInput.defaultSearchTemplate
    public var webSuggestionsEnabled = true

    private let bookmarks: BookmarkLibrary?
    private let history: HistoryStore?
    private let database: AppDatabase?
    private let web: WebSuggestions
    /// Hosts the user visits, by frecency, so "gith⏎" goes to github.com without a database hit.
    private var knownHosts: [(host: String, weight: Double)] = []

    public init(bookmarks: BookmarkLibrary?, history: HistoryStore?, database: AppDatabase?, web: WebSuggestions = WebSuggestions()) {
        self.bookmarks = bookmarks
        self.history = history
        self.database = database
        self.web = web
    }

    /// Refreshes the in-memory host index. Cheap; call at launch and occasionally after visits.
    public func reloadHostIndex() async {
        guard let database else { return }
        let rows = (try? await database.writer.read { db in
            try Row.fetchAll(db, sql: """
                SELECT host, SUM(visitCount + typedCount * 2) AS weight FROM history
                WHERE host != '' GROUP BY host ORDER BY weight DESC LIMIT 2000
                """).map { (host: $0["host"] as String, weight: Double($0["weight"] as Int)) }
        }) ?? []
        knownHosts = rows
    }

    public func noteVisit(host: String) {
        if let index = knownHosts.firstIndex(where: { $0.host == host }) {
            knownHosts[index].weight += 1
        } else {
            knownHosts.append((host, 1))
        }
    }

    // MARK: Local (synchronous)

    public func localResults(for raw: String, limit: Int = 8) -> [Suggestion] {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return [] }
        var results: [Suggestion] = []
        results.append(contentsOf: primaryRows(for: raw, trimmed: text))
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
                ranked.append(Suggestion(id: "cmd:\(command.selector):\(command.title)", kind: .command, title: command.title,
                                         action: .command(command.selector), score: score, shortcut: command.shortcut))
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
        for row in ranked where results.count < limit && !results.contains(where: { $0.id == row.id }) {
            results.append(row)
        }
        return results
    }

    private func primaryRows(for raw: String, trimmed text: String) -> [Suggestion] {
        if let (search, query) = KeywordSearch.match(raw, in: keywordSearches) {
            guard !query.isEmpty, let url = search.url(for: query) else { return [] }
            return [Suggestion(id: "kw:\(search.keyword)", kind: .keyword, title: query,
                               subtitle: "Search \(search.name)", action: .open(url), score: 10,
                               iconHost: url.host())]
        }

        var rows: [Suggestion] = []
        let resolved = AddressInput.resolve(text, searchTemplate: searchTemplate)
        let isSearch = resolved.map { AddressInput.searchURL(for: text, template: searchTemplate) == $0 } ?? true

        if isSearch, !text.contains(" "), let host = completedHost(for: text) {
            let url = URL(string: "https://\(host)")!
            rows.append(Suggestion(id: "url:\(url.absoluteString)", kind: .navigate, title: host,
                                   subtitle: "Open", action: .open(url), score: 10, iconHost: host))
        }
        if let resolved {
            if isSearch {
                rows.append(Suggestion(id: "search:\(text)", kind: .search, title: text, subtitle: "Search Google",
                                       action: .open(resolved), score: 9))
            } else {
                rows.insert(Suggestion(id: "url:\(resolved.absoluteString)", kind: .navigate,
                                       title: DisplayURL(resolved).map { $0.host + $0.remainder } ?? resolved.absoluteString,
                                       subtitle: "Open", action: .open(resolved), score: 10,
                                       iconHost: DisplayURL(resolved)?.host), at: 0)
            }
        }
        return rows
    }

    /// The most-visited known host starting with `prefix` (ignoring "www."), when the prefix
    /// is long enough to be deliberate.
    func completedHost(for prefix: String) -> String? {
        let p = prefix.lowercased()
        guard p.count >= 2, p.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return knownHosts.first { $0.host.hasPrefix(p) && $0.weight >= 2 }?.host
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
        return await historyRows + webRows
    }

    private func historyResults(for text: String) async -> [Suggestion] {
        guard let history, let entries = try? await history.search(text, limit: 6) else { return [] }
        let openURLs = Set(tabs().compactMap { $0.url?.absoluteString })
        return entries.compactMap { entry in
            guard !openURLs.contains(entry.url), let url = URL(string: entry.url) else { return nil }
            return Suggestion(id: "url:\(entry.url)", kind: .history, title: entry.title.isEmpty ? entry.url : entry.title,
                              subtitle: entry.url, action: .open(url), score: 0, iconHost: entry.host)
        }
    }

    private func webResults(for text: String) async -> [Suggestion] {
        guard webSuggestionsEnabled, AddressInput.resolve(text).map({ AddressInput.searchURL(for: text) == $0 }) ?? false else { return [] }
        let phrases = await web.suggestions(for: text)
        let template = searchTemplate
        return phrases.prefix(4).compactMap { phrase in
            guard phrase.lowercased() != text.lowercased(), let url = AddressInput.searchURL(for: phrase, template: template) else { return nil }
            return Suggestion(id: "search:\(phrase)", kind: .web, title: phrase, subtitle: nil, action: .open(url), score: 0)
        }
    }
}

/// Search-as-you-type phrases from the search provider. Cancelled per keystroke by the caller.
public struct WebSuggestions: Sendable {
    public var endpoint = "https://suggestqueries.google.com/complete/search?client=firefox&q=%s"

    public init() {}

    public func suggestions(for query: String) async -> [String] {
        guard let url = AddressInput.searchURL(for: query, template: endpoint) else { return [] }
        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 2)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count > 1, let phrases = json[1] as? [String] else { return [] }
        return phrases
    }
}
