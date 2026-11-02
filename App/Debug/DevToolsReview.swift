#if DEBUG
import AppKit
import BrowserKit
import SwiftUI

/// Captures real native views for repeatable visual review, without screen-recording access.
@MainActor enum ReviewSnapshot {
    /// Writes `view` as `<name>.png` under `.impeccable/review/<folder>` in the repository.
    static func save(_ view: NSView, folder: String, name: String) throws {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent(".impeccable/review/\(folder)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try png.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
    }

    static func find<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        if let match = view as? View, !match.isHiddenOrHasHiddenAncestor { return match }
        for child in view.subviews { if let match = find(type, in: child) { return match } }
        return nil
    }

    static func appearanceName(_ view: NSView) -> String {
        let match = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua])
        return switch match {
        case .darkAqua: "dark"
        case .accessibilityHighContrastAqua: "light-contrast"
        case .accessibilityHighContrastDarkAqua: "dark-contrast"
        default: "light"
        }
    }
}

@MainActor enum DevToolsReview {
    static func saveSnapshot() {
        guard let content = NSApp.keyWindow?.contentView, let host = ReviewSnapshot.find(NSHostingView<DevPanel>.self, in: content) else { return }
        let model = host.rootView.model
        let name = "\(model.section.rawValue.lowercased())-\(ReviewSnapshot.appearanceName(host))-\(model.isDetached ? "detached" : "docked")-\(Int(host.bounds.width))"
        do { try ReviewSnapshot.save(host, folder: "devtools", name: name) }
        catch { model.status = "Could not save review snapshot: \(error.localizedDescription)" }
    }
}

@MainActor enum SettingsReview {
    /// The whole browser window around the Settings tab, so the page reads in its chrome.
    static func saveSnapshot(suffix: String = "") {
        let window = NSApp.orderedWindows.first { $0.windowController is BrowserWindowController }
        guard let content = window?.contentView, let host = ReviewSnapshot.find(SettingsHostingView.self, in: content) else { return }
        let name = "settings-\(ReviewSnapshot.appearanceName(host))-\(Int(content.bounds.width))" + (suffix.isEmpty ? "" : "-\(suffix)")
        try? ReviewSnapshot.save(content, folder: "settings", name: name)
    }

    /// Types into the visible Settings page's search field.
    static func search(_ query: String) { model?.query = query }

    /// Opens a new, empty keyword in the editor, showing its validation.
    static func addKeyword() { model?.addKeyword() }

    private static var model: SettingsModel? {
        let window = NSApp.orderedWindows.first { $0.windowController is BrowserWindowController }
        guard let content = window?.contentView else { return nil }
        return ReviewSnapshot.find(SettingsHostingView.self, in: content)?.rootView.model
    }
}
#endif

#if DEBUG
/// The home page's Reviews with synthetic pull requests, for review captures. Nothing here reaches GitHub.
@MainActor enum HomeReview {
    static func saveSnapshot(suffix: String = "") {
        let window = NSApp.orderedWindows.first { $0.windowController is BrowserWindowController }
        guard let content = window?.contentView, let host = ReviewSnapshot.find(HomeHostingView.self, in: content) else { return }
        let name = "home-\(ReviewSnapshot.appearanceName(host))-\(Int(content.bounds.width))" + (suffix.isEmpty ? "" : "-\(suffix)")
        try? ReviewSnapshot.save(content, folder: "home", name: name)
    }

    /// "populated", "truncated", "empty", "loading", "error", or "signed-out".
    static func showFixture(_ state: String) {
        let github = GitHubService.shared
        switch state {
        case "empty": github.showFixture(GitHubPulls(), signedIn: true)
        case "loading": github.showFixture(nil, signedIn: true)
        case "error": github.showFixture(nil, signedIn: true, error: "GitHub didn’t respond (HTTP 502).")
        case "signed-out": github.showFixture(nil, signedIn: false)
        case "truncated":
            var pulls = sample
            pulls.reviewRequestedTotal = 73
            github.showFixture(pulls, signedIn: true)
        default: github.showFixture(sample, signedIn: true)
        }
        PullSummarizer.shared.showFixture(sampleSummaries, pending: ["koala-labs/koala#31"])
    }

    /// Types into the visible Reviews search field, switches its tab with "tab:mine", or moves the selection with "down".
    static func search(_ query: String) {
        guard let model else { return }
        switch query {
        case "tab:mine": model.tab = .mine
        case "tab:requested": model.tab = .requested
        // The same path as the arrow keys in the search field.
        case "down": model.moveSelection(by: 1)
        default: model.query = query
        }
    }

    private static var model: ReviewsModel? {
        let window = NSApp.orderedWindows.first { $0.windowController is BrowserWindowController }
        guard let content = window?.contentView else { return nil }
        return ReviewSnapshot.find(HomeHostingView.self, in: content)?.rootView.model.reviews
    }

    private static var sample: GitHubPulls {
        let now = Date()
        func pull(_ repo: String, _ number: Int, _ title: String, author: String, hours: Double, age: Double, add: Int, del: Int,
                  checks: GitHubStatus.Checks, draft: Bool = false, bot: Bool = false, team: String? = nil, decision: String? = nil, head: String,
                  body: String? = nil, files: [String] = [], labels: [String] = [], comments: Int = 0,
                  reviews: [GitHubPull.Review] = [], waiting: [String] = []) -> GitHubPull {
            GitHubPull(repo: repo, number: number, title: title, url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
                       author: author, isBot: bot, isDraft: draft, createdAt: now.addingTimeInterval(-age * 86_400),
                       updatedAt: now.addingTimeInterval(-hours * 3600), additions: add, deletions: del,
                       headRef: head, baseRef: "main", reviewDecision: decision, checks: checks,
                       isTeamRequest: team != nil, requestedTeam: team, body: body, changedFiles: files.count, files: files,
                       labels: labels, commentCount: comments, reviews: reviews, pendingReviewers: waiting)
        }
        let requested = [
            pull("koala-labs/api", 412, "Fix token refresh race when two requests expire together", author: "mira", hours: 2, age: 9,
                 add: 48, del: 9, checks: .passing, head: "fix/refresh-race",
                 body: """
                 <!-- What does this change, and why? -->
                 ## Summary

                 Two concurrent 401s both call `refresh()`, and the second overwrites the new token with a stale one. \
                 Refreshes now wait behind one shared task.

                 ## Checklist
                 - [x] Tests
                 - [ ] Docs

                 Closes #398
                 """,
                 files: ["Sources/Auth/TokenStore.swift", "Sources/Auth/RefreshCoordinator.swift", "Sources/Network/Client.swift",
                         "Tests/AuthTests/RefreshTests.swift"],
                 labels: ["bug", "auth"], comments: 3, reviews: [.init(login: "ana", state: .approved)], waiting: ["josh"]),
            pull("koala-labs/tools", 77, "Bump swift-syntax to 601.0.1", author: "renovate", hours: 3, age: 2,
                 add: 2, del: 2, checks: .pending, bot: true, team: "platform", head: "renovate/swift-syntax",
                 body: "This PR contains the following updates:\n\n| Package | Change |\n|---|---|\n| swift-syntax | 600.0.1 → 601.0.1 |",
                 files: ["Package.resolved", "Package.swift"], labels: ["dependencies"], waiting: ["platform"]),
            pull("koala-labs/app", 88, "Migrate the review queue cache to GRDB", author: "devon", hours: 26, age: 8,
                 add: 210, del: 64, checks: .failing, team: "platform", head: "devon/queue-grdb",
                 body: "Replaces the JSON file cache with a GRDB table so the queue survives relaunch and loads without parsing.",
                 files: ["App/Cache/QueueCache.swift", "App/Cache/QueueRecord.swift", "App/Cache/Migrations.swift", "App/Storage/Database.swift",
                         "App/Storage/Pool.swift", "App/Queue/QueueModel.swift", "Tests/CacheTests/QueueCacheTests.swift"],
                 labels: ["storage"], comments: 11,
                 reviews: [.init(login: "sam", state: .changesRequested), .init(login: "jo", state: .approved)], waiting: ["platform"]),
            pull("koala-labs/koala", 31, "Animate Peek promote to tab without a reload", author: "sam", hours: 72, age: 3,
                 add: 12, del: 3, checks: .passing, head: "sam/peek-promote",
                 files: ["App/Window/PeekController.swift", "App/Window/TabStrip.swift"], waiting: ["josh"]),
            pull("koala-labs/koala", 40, "Split view focus line follows the key pane", author: "jo", hours: 96, age: 4,
                 add: 80, del: 21, checks: .none, draft: true, head: "jo/split-focus",
                 body: "WIP", files: ["App/Window/SplitView.swift"]),
            pull("koala-labs/ios", 1204, "Keep the share sheet open while a large export finishes", author: "ana", hours: 144, age: 12,
                 add: 1342, del: 410, checks: .passing, team: "ios", head: "ana/share-export",
                 body: "Exports over 50 MB used to dismiss the share sheet before the file was ready, so the share silently failed.",
                 files: (1...23).map { "Sources/Export/Export\($0).swift" } + ["Sources/Share/ShareSheet.swift", "Sources/Share/Progress.swift"],
                 labels: ["ios", "export"], comments: 5, reviews: [.init(login: "mira", state: .approved), .init(login: "devon", state: .approved)]),
            pull("koala-labs/api", 398, "Rate limit GraphQL search per installation", author: "mira", hours: 300, age: 21,
                 add: 156, del: 40, checks: .failing, head: "mira/search-limit",
                 body: "Adds a token bucket per installation in front of search so one noisy app can't exhaust the shared budget.",
                 files: ["Sources/GraphQL/Search.swift", "Sources/GraphQL/RateLimiter.swift", "Sources/Config/Limits.swift"],
                 comments: 1),
        ]
        let mine = [
            pull("koala-labs/koala", 29, "Tear tabs off into windows", author: "josh", hours: 1, age: 2, add: 412, del: 88,
                 checks: .failing, decision: "APPROVED", head: "josh/tear-off",
                 body: "Dragging a tab out of the strip opens it in a new window at the drop point, keeping its back history.",
                 files: ["App/Window/TabStrip.swift", "App/Window/TabDrag.swift", "App/Window/BrowserWindowController.swift",
                         "Packages/BrowserKit/Sources/BrowserKit/Model/TabCollection.swift"],
                 comments: 4, reviews: [.init(login: "sam", state: .approved)]),
            pull("koala-labs/koala", 33, "Open failing checks from the context chip", author: "josh", hours: 20, age: 5, add: 64, del: 12,
                 checks: .passing, decision: "REVIEW_REQUIRED", head: "josh/failing-checks",
                 files: ["App/GitHub/GitHubViews.swift", "App/Window/ContextChip.swift"], waiting: ["mira", "platform"]),
            pull("koala-labs/api", 420, "Accept fine-grained tokens for webhooks", author: "josh", hours: 50, age: 6, add: 230, del: 31,
                 checks: .pending, decision: "CHANGES_REQUESTED", head: "josh/fine-grained",
                 body: "Webhook delivery now validates fine-grained personal access tokens as well as classic ones.",
                 files: ["Sources/Webhooks/Auth.swift", "Sources/Webhooks/Delivery.swift", "Tests/WebhookTests/AuthTests.swift"],
                 comments: 7, reviews: [.init(login: "mira", state: .changesRequested)]),
        ]
        return GitHubPulls(reviewRequested: requested, mine: mine, reviewRequestedTotal: requested.count, mineTotal: mine.count)
    }

    /// Written summaries for the sample: #31 is still being written, and #77 and #40 fall back to
    /// the author's words and the areas.
    private static let sampleSummaries: [GitHubPull.ID: PullSummary] = [
        "koala-labs/api#412": PullSummary(
            gist: "Serializes token refresh so concurrent 401s can’t overwrite a fresh token",
            overview: "When two requests expire together, both trigger a refresh and the slower one stores a stale token. Refreshes now share one in-flight task in a new RefreshCoordinator, with tests for the race."),
        "koala-labs/app#88": PullSummary(
            gist: "Moves the review queue cache from a JSON file to a GRDB table",
            overview: "The queue cache becomes a GRDB table with a migration, so it survives relaunch and loads without parsing JSON. QueueModel reads through the new storage pool."),
        "koala-labs/ios#1204": PullSummary(
            gist: "Keeps the share sheet open until large exports finish writing",
            overview: "Exports over 50 MB dismissed the share sheet before the file existed, so sharing silently failed. The sheet now waits on export progress. Most of the diff restructures the export pipeline."),
        "koala-labs/api#398": PullSummary(
            gist: "Adds a per-installation token bucket in front of GraphQL search",
            overview: "One noisy installation could exhaust the shared search budget. A token bucket per installation now gates search, with its limits in config."),
        "koala-labs/koala#29": PullSummary(
            gist: "Drags a tab out of the strip into its own window, keeping history",
            overview: "Dropping a dragged tab outside the strip opens a new window at the drop point with the tab’s back history. TabCollection gains a move between windows."),
        "koala-labs/koala#33": PullSummary(
            gist: "Opens a pull request’s failing check straight from the context chip",
            overview: "The tab’s context chip links its first failing check, so a red build is one click from its log."),
        "koala-labs/api#420": PullSummary(
            gist: "Validates fine-grained personal access tokens on webhook delivery",
            overview: "Webhook delivery accepted only classic tokens. It now validates fine-grained tokens too, with tests for both kinds."),
    ]
}
#endif
