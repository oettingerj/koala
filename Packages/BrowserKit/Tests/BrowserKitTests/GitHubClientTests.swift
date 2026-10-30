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
            "author":{"__typename":"User","login":"mira","avatarUrl":"https://avatars.githubusercontent.com/u/2?s=40"},
            "commits":{"nodes":[{"commit":{"statusCheckRollup":{"state":"PENDING"}}}]},
            "reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"User"}}]}},
           {"number":2,"title":"Team","url":"https://github.com/a/c/pull/2","repository":{"nameWithOwner":"a/c"},
            "isDraft":true,"author":{"__typename":"Bot","login":"renovate"},"commits":{"nodes":[]},
            "reviewRequests":{"nodes":[{"requestedReviewer":{"__typename":"User"}},{"requestedReviewer":{"__typename":"Team","name":"platform"}}]}}]},
         "mine":{"issueCount":0,"nodes":[]}}
        """)
        let pulls = GitHubClient.decodePulls(data)
        #expect(pulls.reviewRequested.map(\.id) == ["a/b#1", "a/c#2"])
        #expect(pulls.reviewRequested.map(\.isTeamRequest) == [false, true])
        #expect(pulls.reviewRequestedTotal == 73)
        let direct = pulls.reviewRequested[0]
        #expect(direct.author == "mira")
        #expect(!direct.isBot)
        #expect(direct.checks == .pending)
        #expect(direct.additions == 48 && direct.deletions == 9)
        #expect(direct.headRef == "fix/refresh")
        #expect(direct.updatedAt == (try Date("2026-10-29T08:30:00Z", strategy: .iso8601)))
        let team = pulls.reviewRequested[1]
        #expect(team.requestedTeam == "platform")
        #expect(team.isDraft)
        #expect(team.isBot)
        #expect(team.checks == GitHubStatus.Checks.none)
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
