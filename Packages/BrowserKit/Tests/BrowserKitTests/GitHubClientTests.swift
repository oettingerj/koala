import Foundation
import Testing
@testable import BrowserKit

@Suite struct GitHubDecodingTests {
    private func json(_ text: String) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: Data(text.utf8)) as! [String: Any]
    }

    @Test func decodesPullRequestWithChecks() throws {
        let node = json("""
        {"__typename":"PullRequest","title":"Fix crash","state":"OPEN","isDraft":false,"reviewDecision":"REVIEW_REQUIRED",
         "headRefName":"fix/crash","baseRefName":"main","mergeable":"MERGEABLE",
         "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE","contexts":{"nodes":[
           {"__typename":"CheckRun","name":"lint","conclusion":"SUCCESS","status":"COMPLETED","detailsUrl":"https://ci/1"},
           {"__typename":"CheckRun","name":"test","conclusion":"FAILURE","status":"COMPLETED","detailsUrl":"https://ci/2"},
           {"__typename":"CheckRun","name":"build","conclusion":null,"status":"IN_PROGRESS","detailsUrl":null},
           {"__typename":"StatusContext","context":"ci/legacy","state":"SUCCESS","targetUrl":"https://ci/3"}]}}}}]},
         "reviewRequests":{"nodes":[{"requestedReviewer":{"login":"octocat"}},{"requestedReviewer":{"name":"core"}}]}}
        """)
        let status = try #require(GitHubClient.decodeStatus(node))
        #expect(status.state == .open)
        #expect(status.checks == .failing)
        #expect(status.checkRuns.map(\.name) == ["test", "build", "lint", "ci/legacy"])
        #expect(status.reviewers == ["octocat", "core"])
        #expect(status.headRef == "fix/crash")
    }

    @Test func decodesDraftMergedAndIssues() throws {
        #expect(GitHubClient.decodeStatus(json(#"{"__typename":"PullRequest","title":"x","state":"OPEN","isDraft":true}"#))?.state == .draft)
        #expect(GitHubClient.decodeStatus(json(#"{"__typename":"PullRequest","title":"x","state":"MERGED"}"#))?.state == .merged)
        #expect(GitHubClient.decodeStatus(json(#"{"__typename":"Issue","title":"x","state":"CLOSED","stateReason":"NOT_PLANNED"}"#))?.state
                == .issueClosed(completed: false))
        #expect(GitHubClient.decodeStatus(json(#"{"__typename":"Issue","state":"OPEN"}"#)) == nil)
    }

    @Test func queueKeepsReviewRequestsAndOnlyFailingOwnPRs() {
        let data = json("""
        {"review":{"nodes":[{"number":1,"title":"Review me","url":"https://github.com/a/b/pull/1","repository":{"nameWithOwner":"a/b"}}]},
         "mine":{"nodes":[
           {"number":2,"title":"Green","url":"https://github.com/a/b/pull/2","repository":{"nameWithOwner":"a/b"},
            "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"SUCCESS"}}}]}},
           {"number":3,"title":"Red","url":"https://github.com/a/b/pull/3","repository":{"nameWithOwner":"a/b"},
            "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"FAILURE"}}}]}}]}}
        """)
        let queue = GitHubClient.decodePulls(data).queue
        #expect(queue.map(\.id) == ["a/b#1", "a/b#3"])
        #expect(queue.map(\.reason) == [.reviewRequested, .failingChecks])
    }

    @Test func pullsTellDirectFromTeamRequests() throws {
        let data = json("""
        {"direct":{"nodes":[{"number":1,"repository":{"nameWithOwner":"a/b"}}]},
         "review":{"issueCount":73,"nodes":[
           {"number":1,"title":"Direct","url":"https://github.com/a/b/pull/1","repository":{"nameWithOwner":"a/b"},
            "isDraft":false,"createdAt":"2026-10-01T12:00:00Z","updatedAt":"2026-10-29T08:30:00Z","additions":48,"deletions":9,
            "headRefName":"fix/refresh","baseRefName":"main","reviewDecision":"REVIEW_REQUIRED",
            "author":{"login":"mira","avatarUrl":"https://avatars.githubusercontent.com/u/2?s=40"},
            "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"PENDING"}}}]},
            "reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"User"}}]}},
           {"number":2,"title":"Team","url":"https://github.com/a/c/pull/2","repository":{"nameWithOwner":"a/c"},
            "isDraft":true,"author":null,"commits":{"nodes":[]},
            "reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"User"}},{"requestedReviewer":{"__typename":"Team","name":"platform"}}]}}]},
         "mine":{"issueCount":0,"nodes":[]}}
        """)
        let pulls = GitHubClient.decodePulls(data)
        #expect(pulls.reviewRequested.map(\.id) == ["a/b#1", "a/c#2"])
        #expect(pulls.reviewRequested.map(\.isTeamRequest) == [false, true])
        #expect(pulls.reviewRequestedTotal == 73)
        let direct = pulls.reviewRequested[0]
        #expect(direct.author == "mira")
        #expect(direct.checks == .pending)
        #expect(direct.additions == 48 && direct.deletions == 9)
        #expect(direct.headRef == "fix/refresh")
        #expect(direct.updatedAt == (try Date("2026-10-29T08:30:00Z", strategy: .iso8601)))
        let team = pulls.reviewRequested[1]
        #expect(team.requestedTeam == "platform")
        #expect(team.isDraft)
        #expect(team.author == nil)
        #expect(team.checks == GitHubStatus.Checks.none)
    }

    @Test func decodesPullRequestForBranch() {
        let found = json(#"{"repository":{"pullRequests":{"nodes":[{"url":"https://github.com/a/b/pull/7"}]}}}"#)
        #expect(GitHubClient.decodePullRequestURL(found)?.absoluteString == "https://github.com/a/b/pull/7")
        #expect(GitHubClient.decodePullRequestURL(json(#"{"repository":{"pullRequests":{"nodes":[]}}}"#)) == nil)
        #expect(GitHubClient.decodePullRequestURL(json(#"{"repository":null}"#)) == nil)
    }

    @Test func failingQueueItemsLeadToChecks() {
        let url = URL(string: "https://github.com/a/b/pull/3")!
        #expect(GitHubQueueItem(repo: "a/b", number: 3, title: "", url: url, reason: .failingChecks).destination.absoluteString
                == "https://github.com/a/b/pull/3/checks")
        #expect(GitHubQueueItem(repo: "a/b", number: 3, title: "", url: url, reason: .reviewRequested).destination == url)
    }

    @Test func decodesViewer() {
        let account = GitHubClient.decodeViewer(json(#"{"viewer":{"login":"octocat","name":"","avatarUrl":"https://avatars.githubusercontent.com/u/1"}}"#))
        #expect(account == GitHubAccount(login: "octocat", name: nil, avatarURL: URL(string: "https://avatars.githubusercontent.com/u/1")))
        #expect(GitHubClient.decodeViewer(json(#"{"viewer":null}"#)) == nil)
    }
}

@Suite struct LocalClonesTests {
    @Test(arguments: [
        ("git@github.com:SwiftLang/Swift.git", "swiftlang/swift"),
        ("https://github.com/apple/swift-format", "apple/swift-format"),
        ("ssh://git@github.com/a/b.git", "a/b"),
        ("https://gitlab.com/a/b.git", nil as String?),
    ])
    func parsesRemotes(remote: String, slug: String?) {
        #expect(LocalClones.slug(fromRemote: remote) == slug)
    }

    @Test func scansAndResolvesFilesSafely() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("clones-\(UUID())")
        let clone = root.appendingPathComponent("work/swift")
        try FileManager.default.createDirectory(at: clone.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try """
        [remote "origin"]
            url = git@github.com:swiftlang/swift.git
        """.write(to: clone.appendingPathComponent(".git/config"), atomically: true, encoding: .utf8)
        let clones = LocalClones.scan(root: root)
        let blob = try #require(GitHubURL(URL(string: "https://github.com/swiftlang/swift/blob/main/lib/AST/Decl.cpp#L42")))
        let file = try #require(clones.file(for: blob))
        #expect(file.url.path.hasSuffix("work/swift/lib/AST/Decl.cpp"))
        #expect(file.line == 42)
        let escape = GitHubURL(owner: "swiftlang", repo: "swift", kind: .blob(ref: "main", path: "../../etc/passwd", lines: nil))
        #expect(clones.file(for: escape) == nil)
    }

    @Test func readsCheckedOutBranch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("branch-\(UUID())")
        let clone = root.appendingPathComponent("repo")
        try FileManager.default.createDirectory(at: clone.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/feature/login\n".write(to: clone.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(LocalClones.currentBranch(at: clone) == "feature/login")

        try "4b825dc642cb6eb9a060e54bf8d69288fbee4904\n".write(to: clone.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(LocalClones.currentBranch(at: clone) == nil)

        // A worktree's .git is a file pointing at its git directory.
        let worktreeGit = clone.appendingPathComponent(".git/worktrees/wt")
        try FileManager.default.createDirectory(at: worktreeGit, withIntermediateDirectories: true)
        try "ref: refs/heads/wip\n".write(to: worktreeGit.appendingPathComponent("HEAD"), atomically: true, encoding: .utf8)
        let worktree = root.appendingPathComponent("wt")
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)
        try "gitdir: \(worktreeGit.path)\n".write(to: worktree.appendingPathComponent(".git"), atomically: true, encoding: .utf8)
        #expect(LocalClones.currentBranch(at: worktree) == "wip")
        #expect(LocalClones.currentBranch(at: root) == nil)
    }

    @Test func editorURLs() {
        let file = URL(fileURLWithPath: "/Users/me/code/My App/main.swift")
        #expect(CodeEditor.vscode.url(for: file, line: 3)?.absoluteString == "vscode://file/Users/me/code/My%20App/main.swift:3")
        #expect(CodeEditor.xcode.url(for: file, line: 3) == nil)
    }
}
