import AppKit
import BrowserKit
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
    @ObservationIgnored let bookmarks: BookmarkLibrary
    @ObservationIgnored let sessionStore: SessionStore?

    /// Most recent last. Backs ⇧⌘T and History › Recently Closed.
    private(set) var recentlyClosed: [ClosedItem] = []
    private static let recentlyClosedLimit = 25

    @ObservationIgnored var windowSnapshots: () -> [WindowSnapshot] = { [] }
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.joshoettinger.nano", category: "services")

    private init() {
        let database: AppDatabase
        do {
            database = try AppDatabase.openDefault()
        } catch {
            Logger(subsystem: "com.joshoettinger.nano", category: "services")
                .error("Database unavailable, using memory: \(error.localizedDescription)")
            database = try! AppDatabase.inMemory()
        }
        self.database = database
        history = HistoryStore(database: database)
        favicons = FaviconStore(database: database)
        bookmarks = BookmarkLibrary(database: database)
        sessionStore = try? SessionStore.defaultStore()
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
        sessionStore?.save(Session(windows: windowSnapshots(), recentlyClosed: recentlyClosed), sync: sync)
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
    /// for a site Nano has seen before.
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
        webView.evaluateJavaScript(FaviconCandidates.script, in: nil, in: .defaultClient) { [favicons] result in
            let links: [FaviconCandidates.Link]
            if case .success(let value) = result, let json = try? JSONSerialization.data(withJSONObject: value) {
                links = (try? JSONDecoder().decode([FaviconCandidates.Link].self, from: json)) ?? []
            } else {
                links = []
            }
            let candidates = FaviconCandidates.rank(links, pageURL: pageURL)
            Task { @MainActor in
                let data = await favicons.icon(host: host, candidates: candidates)
                guard DisplayURL(tab.url)?.host == host, let data else { return }
                tab.setFavicon(Self.image(data))
            }
        }
    }

    static func image(_ data: Data) -> NSImage? {
        guard let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}
