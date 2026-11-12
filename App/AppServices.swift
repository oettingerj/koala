import AppKit
import BrowserKit
import Eucalyptus
import Observation
import os

/// App-wide stores shared by every window.
@MainActor
@Observable
final class AppServices {
    static let shared = AppServices()

    @ObservationIgnored let database: AppDatabase
    @ObservationIgnored let history: HistoryStore
    @ObservationIgnored let favicons: FaviconStore
    @ObservationIgnored let pullSummaries: PullSummaryStore
    @ObservationIgnored let bookmarks: BookmarkLibrary
    @ObservationIgnored let sessionStore: SessionStore?
    @ObservationIgnored let suggestions: SuggestionEngine
    /// Menu commands snapshot, refreshed whenever a command bar opens.
    @ObservationIgnored var commands: [SuggestionEngine.CommandInfo] = []

    /// Most recent last. Backs ⇧⌘T and History › Recently Closed.
    private(set) var recentlyClosed: [ClosedItem] = []
    /// Bumped per host when a fetch changes its cached icon, so views outside the tab
    /// (the bookmarks bar) can reload it.
    private(set) var faviconRevisions: [String: Int] = [:]
    /// Bumped when history is cleared, so the History page reloads.
    private(set) var historyRevision = 0
    private static let recentlyClosedLimit = 25

    @ObservationIgnored var windowSnapshots: () -> [WindowSnapshot] = { [] }
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.joshoettinger.koala", category: "services")

    private init() {
        let database: AppDatabase
        do {
            database = try AppDatabase.openDefault()
        } catch {
            Logger(subsystem: "com.joshoettinger.koala", category: "services")
                .error("Database unavailable, using memory: \(error.localizedDescription)")
            database = try! AppDatabase.inMemory()
        }
        self.database = database
        history = HistoryStore(database: database)
        favicons = FaviconStore(database: database)
        pullSummaries = PullSummaryStore(database: database)
        bookmarks = BookmarkLibrary(database: database)
        sessionStore = try? SessionStore.defaultStore()
        suggestions = SuggestionEngine(bookmarks: bookmarks, history: history, database: database)
        suggestions.tabs = {
            // A private window's tabs show only in its own command bar.
            NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
                .filter { !$0.isPrivate || $0.window?.isKeyWindow == true }
                .flatMap { $0.tabs.tabs }
                .map { SuggestionEngine.TabInfo(id: $0.id, title: $0.displayTitle, url: $0.url) }
        }
        suggestions.commands = { [unowned self] in commands }
        suggestions.extraRemote = [
            { text in GitHubService.shared.queueSuggestions(for: text) },
            { text in await GitHubService.shared.repositorySuggestions(for: text) },
        ]
        suggestions.zeroState = { [unowned self] in
            let queue = GitHubService.shared.queueRows(matching: nil).prefix(4)
            // Newest first, keeping each item's index into `recentlyClosed` for reopening.
            let closed = recentlyClosed.enumerated().reversed().prefix(3).compactMap { index, item -> Suggestion? in
                guard case .tab(let tab, _) = item else { return nil }
                return Suggestion(id: "closed:\(tab.id)", kind: .closed, title: item.title, subtitle: tab.url?.absoluteString,
                                  action: .reopenClosed(index), score: 0, iconHost: DisplayURL(tab.url)?.host)
            }
            return Array(queue) + closed
        }
        Task { await suggestions.reloadHostIndex() }
    }

    // MARK: Session

    func loadSession() -> Session? {
        let session = sessionStore?.load()
        recentlyClosed = session?.recentlyClosed ?? []
        return session
    }

    /// Coalesces bursts of tab changes into one write a second later.
    func scheduleSessionSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.saveSession(sync: false)
        }
    }

    func saveSession(sync: Bool) {
        saveTask?.cancel()
        sessionStore?.save(Session(windows: windowSnapshots(), recentlyClosed: recentlyClosed, savedAt: Date()), sync: sync)
    }

    func clearHistory(since date: Date?) async {
        try? await history.clear(since: date)
        historyRevision += 1
    }

    // MARK: Recently closed

    func remember(_ item: ClosedItem) {
        recentlyClosed.append(item)
        if recentlyClosed.count > Self.recentlyClosedLimit {
            recentlyClosed.removeFirst(recentlyClosed.count - Self.recentlyClosedLimit)
        }
        scheduleSessionSave()
    }

    func takeRecentlyClosed(at index: Int? = nil) -> ClosedItem? {
        guard !recentlyClosed.isEmpty else { return nil }
        let index = index ?? recentlyClosed.count - 1
        guard recentlyClosed.indices.contains(index) else { return nil }
        let item = recentlyClosed.remove(at: index)
        scheduleSessionSave()
        return item
    }

    // MARK: Favicons

    /// Shows the cached icon immediately on commit, so a tab never flashes the placeholder
    /// for a site Koala has seen before.
    func applyCachedFavicon(to tab: Tab) {
        guard let host = DisplayURL(tab.url)?.host else { return tab.setFavicon(nil) }
        Task {
            let data = await favicons.cached(host: host)
            guard DisplayURL(tab.url)?.host == host else { return }
            tab.setFavicon(data.flatMap(Self.image))
        }
    }

    /// After a load finishes, reads the page's declared icons and refreshes the cache.
    func refreshFavicon(for tab: Tab) {
        guard let webView = tab.webView, let pageURL = tab.url, let host = DisplayURL(pageURL)?.host else { return }
        webView.evaluateJavaScript(FaviconCandidates.script, in: nil, in: .defaultClient) { [self] result in
            let links: [FaviconCandidates.Link]
            if case .success(let value) = result, let json = try? JSONSerialization.data(withJSONObject: value) {
                links = (try? JSONDecoder().decode([FaviconCandidates.Link].self, from: json)) ?? []
            } else {
                links = []
            }
            let candidates = FaviconCandidates.rank(links, pageURL: pageURL)
            let store = webView.configuration.websiteDataStore.httpCookieStore
            Task { @MainActor in
                let previous = await favicons.cached(host: host)
                // Cookies go only to the page's own host: enough for icons behind a sign-in,
                // without handing a CDN or another site cookies a tab icon doesn't need.
                let data = await favicons.icon(host: host, candidates: candidates) { @MainActor url in
                    guard url.host() == pageURL.host() else { return [] }
                    return BackgroundFetch.cookies(await store.allCookies(), for: url)
                }
                if let data, data != previous { faviconRevisions[host, default: 0] += 1 }
                guard DisplayURL(tab.url)?.host == host, let data else { return }
                tab.setFavicon(Self.image(data))
            }
        }
    }

    /// SVG favicons with a `prefers-color-scheme: dark` block render as broken outlines in
    /// AppKit's SVG renderer (docs.rs becomes a hollow ring). Dropping the block keeps the
    /// light shape; FaviconContrast tints dark glyphs for dark chrome.
    static func lightOnlySVG(_ data: Data) -> Data? {
        guard data.count < 512 * 1024, var text = String(data: data, encoding: .utf8),
              text.contains("<svg"), text.contains("prefers-color-scheme") else { return nil }
        while let start = text.range(of: "@media (prefers-color-scheme: dark)")
                ?? text.range(of: "@media(prefers-color-scheme:dark)") {
            guard let open = text[start.upperBound...].firstIndex(of: "{") else { break }
            var depth = 0
            var end = open
            for index in text[open...].indices {
                if text[index] == "{" { depth += 1 }
                if text[index] == "}" { depth -= 1; if depth == 0 { end = index; break } }
            }
            guard depth == 0 else { break }
            text.removeSubrange(start.lowerBound...end)
        }
        return text.data(using: .utf8)
    }

    static func image(_ data: Data) -> NSImage? {
        guard let image = NSImage(data: lightOnlySVG(data) ?? data) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
