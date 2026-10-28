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
        let queue = GitHubClient.decodeQueue(data)
        #expect(queue.map(\.id) == ["a/b#1", "a/b#3"])
        #expect(queue.map(\.reason) == [.reviewRequested, .failingChecks])
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

    @Test func editorURLs() {
        let file = URL(fileURLWithPath: "/Users/me/code/My App/main.swift")
        #expect(CodeEditor.vscode.url(for: file, line: 3)?.absoluteString == "vscode://file/Users/me/code/My%20App/main.swift:3")
        #expect(CodeEditor.xcode.url(for: file, line: 3) == nil)
    }
}
