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
                  checks: GitHubStatus.Checks, draft: Bool = false, team: String? = nil, decision: String? = nil, head: String) -> GitHubPull {
            GitHubPull(repo: repo, number: number, title: title, url: URL(string: "https://github.com/\(repo)/pull/\(number)")!,
                       author: author, isDraft: draft, createdAt: now.addingTimeInterval(-age * 86_400),
                       updatedAt: now.addingTimeInterval(-hours * 3600), additions: add, deletions: del,
                       headRef: head, baseRef: "main", reviewDecision: decision, checks: checks,
                       isTeamRequest: team != nil, requestedTeam: team)
        }
        let requested = [
            pull("koala-labs/api", 412, "Fix token refresh race when two requests expire together", author: "mira", hours: 2, age: 9,
                 add: 48, del: 9, checks: .passing, head: "fix/refresh-race"),
            pull("koala-labs/tools", 77, "Bump swift-syntax to 601.0.1", author: "renovate", hours: 3, age: 2,
                 add: 2, del: 2, checks: .pending, team: "platform", head: "renovate/swift-syntax"),
            pull("koala-labs/app", 88, "Migrate the review queue cache to GRDB", author: "devon", hours: 26, age: 8,
                 add: 210, del: 64, checks: .failing, team: "platform", head: "devon/queue-grdb"),
            pull("koala-labs/koala", 31, "Animate Peek promote to tab without a reload", author: "sam", hours: 72, age: 3,
                 add: 12, del: 3, checks: .passing, head: "sam/peek-promote"),
            pull("koala-labs/koala", 40, "Split view focus line follows the key pane", author: "jo", hours: 96, age: 4,
                 add: 80, del: 21, checks: .none, draft: true, head: "jo/split-focus"),
            pull("koala-labs/ios", 1204, "Keep the share sheet open while a large export finishes", author: "ana", hours: 144, age: 12,
                 add: 1342, del: 410, checks: .passing, team: "ios", head: "ana/share-export"),
            pull("koala-labs/api", 398, "Rate limit GraphQL search per installation", author: "mira", hours: 300, age: 21,
                 add: 156, del: 40, checks: .failing, head: "mira/search-limit"),
        ]
        let mine = [
            pull("koala-labs/koala", 29, "Tear tabs off into windows", author: "josh", hours: 1, age: 2, add: 412, del: 88,
                 checks: .failing, decision: "APPROVED", head: "josh/tear-off"),
            pull("koala-labs/koala", 33, "Open failing checks from the context chip", author: "josh", hours: 20, age: 5, add: 64, del: 12,
                 checks: .passing, decision: "REVIEW_REQUIRED", head: "josh/failing-checks"),
            pull("koala-labs/api", 420, "Accept fine-grained tokens for webhooks", author: "josh", hours: 50, age: 6, add: 230, del: 31,
                 checks: .pending, decision: "CHANGES_REQUESTED", head: "josh/fine-grained"),
        ]
        return GitHubPulls(reviewRequested: requested, mine: mine, reviewRequestedTotal: requested.count, mineTotal: mine.count)
    }
}
#endif
