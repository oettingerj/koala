import AppKit
import BrowserKit
import Observation
import os

/// App-wide GitHub state: sign-in, live PR/issue status for open tabs, the review queue,
/// and local clones for "Open in Editor".
@MainActor
@Observable
final class GitHubService {
    static let shared = GitHubService()

    private(set) var isSignedIn = GitHubKeychain.read() != nil
    private(set) var statuses: [GitHubClient.Key: GitHubStatus] = [:]
    private(set) var queue: [GitHubQueueItem] = []
    private(set) var clones = LocalClones()
    private(set) var lastError: String?

    var editor: CodeEditor {
        get { CodeEditor(rawValue: UserDefaults.standard.string(forKey: "CodeEditor") ?? "") ?? .vscode }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "CodeEditor") }
    }

    private(set) var codeRoot: URL?

    @ObservationIgnored let client = GitHubClient(token: { GitHubKeychain.read() })
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let log = Logger(subsystem: "com.joshoettinger.koala", category: "github")
    private static let pollInterval: Duration = .seconds(60)

    private init() {
        restoreCodeRoot()
        startPolling()
    }

    // MARK: Status

    func status(for url: URL?) -> GitHubStatus? {
        guard let github = GitHubURL(url), let number = github.number else { return nil }
        return statuses[GitHubClient.Key(owner: github.owner.lowercased(), repo: github.repo.lowercased(), number: number)]
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
            .compactMap { tab in
                guard let github = GitHubURL(tab.url), let number = github.number else { return nil }
                return GitHubClient.Key(owner: github.owner.lowercased(), repo: github.repo.lowercased(), number: number)
            }
    }

    private func refresh(includeQueue: Bool = false) async {
        guard isSignedIn else { return }
        // Polling never runs while the app is in the background; status refreshes on return.
        guard NSApp.isActive || includeQueue else { return }
        do {
            let fresh = try await client.statuses(for: openKeys())
            statuses.merge(fresh) { _, new in new }
            if includeQueue { queue = try await client.reviewQueue() }
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
        statuses = [:]
        queue = []
    }

    // MARK: Local clones

    /// Remembers the folder that holds clones. Security-scoped, which also keeps bookmarks saved while sandboxed working.
    func setCodeRoot(_ url: URL) {
        guard let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        UserDefaults.standard.set(bookmark, forKey: "CodeRootBookmark")
        restoreCodeRoot()
    }

    private func restoreCodeRoot() {
        guard let data = UserDefaults.standard.data(forKey: "CodeRootBookmark") else { return }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource() else { return }
        codeRoot = url
        rescanClones()
    }

    func rescanClones() {
        guard let codeRoot else { return }
        Task.detached(priority: .utility) {
            let found = LocalClones.scan(root: codeRoot)
            await MainActor.run { GitHubService.shared.clones = found }
        }
    }

    /// Opens the file behind a GitHub page in the chosen editor. Returns false when no clone matches.
    @discardableResult
    func openInEditor(_ github: GitHubURL) -> Bool {
        guard let (file, line) = clones.file(for: github) else { return false }
        if let url = editor.url(for: file, line: line) {
            NSWorkspace.shared.open(url)
        } else if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleIdentifier) {
            NSWorkspace.shared.open([file], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
        return true
    }

    // MARK: Command bar

    /// Review queue items and repository search for the command bar.
    func suggestions(for text: String) async -> [Suggestion] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard isSignedIn, query.count >= 2 else { return [] }
        var rows: [Suggestion] = queue.compactMap { item in
            guard let score = FuzzyMatch.score(query, in: "\(item.repo) \(item.title) #\(item.number)"), score >= 0.5 else { return nil }
            return Suggestion(id: "url:\(item.url.absoluteString)", kind: .github, title: item.title,
                              subtitle: "\(item.repo)#\(item.number) · \(item.reason == .reviewRequested ? "review requested" : "checks failing")",
                              action: .open(item.url), score: score, iconHost: "github.com")
        }
        if query.count >= 3, !query.contains(" "), let repos = try? await client.searchRepositories(query) {
            rows += repos.map { repo in
                Suggestion(id: "url:\(repo.url.absoluteString)", kind: .github, title: repo.nameWithOwner,
                           subtitle: repo.description, action: .open(repo.url), score: 0, iconHost: "github.com")
            }
        }
        return rows
    }
}
