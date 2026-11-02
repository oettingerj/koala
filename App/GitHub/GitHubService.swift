import AppKit
import BrowserKit
import Observation
import os

/// App-wide GitHub state: sign-in, live PR/issue status for open tabs, and the review queue.
@MainActor
@Observable
final class GitHubService {
    static let shared = GitHubService()

    private(set) var isSignedIn = GitHubKeychain.read() != nil
    /// Who is signed in, for Settings. Fetched once per sign-in.
    private(set) var account: GitHubAccount?
    private(set) var statuses: [GitHubClient.Key: GitHubStatus] = [:]
    private(set) var pendingStatuses: Set<GitHubClient.Key> = []
    /// Keys fetched for suggestions; a failed fetch isn't retried on every keystroke.
    @ObservationIgnored private var requestedStatuses: Set<GitHubClient.Key> = []
    /// Review requests and your own open pull requests, for the home page's Reviews.
    private(set) var pulls = GitHubPulls()
    /// When `pulls` last arrived; nil until the first fetch after launch or sign-in.
    private(set) var pullsUpdatedAt: Date?
    private(set) var isRefreshingPulls = false
    /// The toolbar's review queue, from `pulls`.
    var queue: [GitHubQueueItem] { pulls.queue }
    private(set) var lastError: String?

    /// Shows how many pull requests wait on your review on the Dock icon.
    var showsDockBadge = UserDefaults.standard.object(forKey: "DockReviewBadge") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsDockBadge, forKey: "DockReviewBadge") }
    }

    /// The Dock badge: review requests only, since your own failing PRs aren't waiting on anyone.
    var dockBadge: String? {
        let count = queue.filter { $0.reason == .reviewRequested }.count
        return showsDockBadge && isSignedIn && count > 0 ? "\(count)" : nil
    }

    @ObservationIgnored let client = GitHubClient(token: { GitHubKeychain.read() })
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.joshoettinger.koala", category: "github")
    private static let pollInterval: Duration = .seconds(60)

    private init() {
        startPolling()
    }

    // MARK: Status

    func status(for url: URL?) -> GitHubStatus? {
        Self.key(for: url).flatMap { statuses[$0] }
    }

    /// Whether a status for `url` is being fetched, so a view can hold space for it.
    func isStatusPending(for url: URL?) -> Bool {
        Self.key(for: url).map(pendingStatuses.contains) ?? false
    }

    /// Fetches state for pull requests and issues shown outside tabs (history, bookmarks, the
    /// review queue in the command bar), once each, in one request.
    func ensureStatus(for urls: [URL]) {
        guard isSignedIn else { return }
        let keys = Set(urls.compactMap(Self.key(for:))).subtracting(requestedStatuses).filter { statuses[$0] == nil }
        guard !keys.isEmpty else { return }
        requestedStatuses.formUnion(keys)
        pendingStatuses.formUnion(keys)
        Task { [weak self, client] in
            let fresh = (try? await client.statuses(for: Array(keys))) ?? [:]
            guard let self else { return }
            self.statuses.merge(fresh) { _, new in new }
            self.pendingStatuses.subtract(keys)
        }
    }

    private static func key(for url: URL?) -> GitHubClient.Key? {
        guard let github = GitHubURL(url), let number = github.number else { return nil }
        return GitHubClient.Key(owner: github.owner.lowercased(), repo: github.repo.lowercased(), number: number)
    }

    /// Coalesces requests from tab switches and loads into one fetch.
    func refreshSoon() {
        guard isSignedIn else { return }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Fetches the review queue now: the Reviews page's refresh button and ⌘R.
    func refreshPulls() {
        guard isSignedIn, !isRefreshingPulls else { return }
        Task { await refresh(includeQueue: true) }
    }

    private func startPolling() {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(includeQueue: true)
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
    }

    private func openKeys() -> [GitHubClient.Key] {
        NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
            .flatMap { $0.tabs.tabs }
            .compactMap { Self.key(for: $0.url) }
    }

    #if DEBUG
    /// Review scripts show synthetic pull requests; polling leaves them alone.
    @ObservationIgnored private var showsFixture = false

    func showFixture(_ pulls: GitHubPulls?, signedIn: Bool, error: String? = nil) {
        showsFixture = true
        isSignedIn = signedIn
        self.pulls = pulls ?? GitHubPulls()
        pullsUpdatedAt = pulls == nil ? nil : Date()
        isRefreshingPulls = signedIn && pulls == nil && error == nil
        lastError = error
    }
    #endif

    private func refresh(includeQueue: Bool = false) async {
        guard isSignedIn else { return }
        #if DEBUG
        if showsFixture { return }
        #endif
        // Polling never runs while the app is in the background; status refreshes on return.
        guard NSApp.isActive || includeQueue else { return }
        if includeQueue { isRefreshingPulls = true }
        defer { if includeQueue { isRefreshingPulls = false } }
        do {
            let fresh = try await client.statuses(for: openKeys())
            statuses.merge(fresh) { _, new in new }
            if includeQueue {
                pulls = try await client.pulls()
                pullsUpdatedAt = Date()
                PullSummarizer.shared.update(pulls.reviewRequested + pulls.mine)
            }
            if account == nil { account = try await client.viewer() }
            lastError = nil
        } catch GitHubClient.Failure.http(401) {
            // Revoked or expired token: sign out rather than retry forever.
            signOut()
            lastError = "GitHub signed you out. Sign in again to restore PR status."
        } catch {
            lastError = "\(error)"
            log.error("GitHub refresh failed: \(String(describing: error), privacy: .public)")
        }
    }

    // MARK: Sign-in

    func didSignIn(token: String) {
        guard GitHubKeychain.save(token) else {
            lastError = "Couldn’t save the GitHub token to the Keychain."
            return
        }
        isSignedIn = true
        lastError = nil
        Task { await refresh(includeQueue: true) }
    }

    func signOut() {
        GitHubKeychain.delete()
        isSignedIn = false
        account = nil
        statuses = [:]
        requestedStatuses = []
        pendingStatuses = []
        pulls = GitHubPulls()
        pullsUpdatedAt = nil
    }

    // MARK: Command bar

    /// Review queue items matching what's typed; answers at once, without the network.
    func queueSuggestions(for text: String) -> [Suggestion] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return [] }
        return queueRows(matching: query)
    }

    /// Repositories matching what's typed, from GitHub search.
    func repositorySuggestions(for text: String) async -> [Suggestion] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard isSignedIn, query.count >= 3, !query.contains(" "),
              let repos = try? await client.searchRepositories(query) else { return [] }
        return repos.map { repo in
            Suggestion(id: "url:\(repo.url.absoluteString)", kind: .github, title: repo.nameWithOwner,
                       subtitle: repo.description, action: .open(repo.url), score: 0, iconHost: "github.com")
        }
    }

    /// Review queue items as suggestions: those matching `query`, or all of them (as the
    /// command bar's Review Queue section) when `query` is nil.
    func queueRows(matching query: String?) -> [Suggestion] {
        guard isSignedIn else { return [] }
        return queue.compactMap { item in
            var score = 0.0
            if let query {
                guard let match = FuzzyMatch.score(query, in: "\(item.repo) \(item.title) #\(item.number)"), match >= 0.5 else { return nil }
                score = match
            }
            return Suggestion(id: "url:\(item.url.absoluteString)", kind: .github, section: query == nil ? .reviewQueue : .github,
                              title: item.title,
                              subtitle: "\(item.repo)#\(item.number) · \(item.reason == .reviewRequested ? "review requested" : "checks failing")",
                              action: .open(item.destination), score: score, iconHost: "github.com")
        }
    }
}
