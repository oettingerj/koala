import Foundation

/// Live state of a pull request or issue, as shown in the tab strip and context chip.
public struct GitHubStatus: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case open, draft, merged, closed
        case issueOpen
        case issueClosed(completed: Bool)
    }

    public enum Checks: Equatable, Sendable { case none, pending, passing, failing }

    public struct Check: Equatable, Sendable, Identifiable {
        public var name: String
        public var result: Checks
        public var url: URL?
        public var id: String { name }
    }

    public var title: String
    public var state: State
    public var checks: Checks
    public var checkRuns: [Check]
    public var reviewDecision: String?
    public var headRef: String?
    public var baseRef: String?
    public var mergeable: String?
    public var reviewers: [String]
}

/// An item in the review queue.
public struct GitHubQueueItem: Equatable, Sendable, Identifiable {
    public enum Reason: Sendable, Equatable { case reviewRequested, failingChecks }
    public var repo: String
    public var number: Int
    public var title: String
    public var url: URL
    public var reason: Reason
    public var id: String { "\(repo)#\(number)" }
}

/// The signed-in user, shown in Settings.
public struct GitHubAccount: Equatable, Sendable {
    public var login: String
    public var name: String?
    public var avatarURL: URL?
}

public struct GitHubRepository: Equatable, Sendable {
    public var nameWithOwner: String
    public var description: String?
    public var url: URL
}

/// Minimal GitHub API client: hand-written GraphQL for status, REST for permalinks.
/// The token is read per request from the provider and sent only to api.github.com.
public actor GitHubClient {
    public typealias TokenProvider = @Sendable () -> String?

    private let token: TokenProvider
    private let session: URLSession
    private var rateLimitedUntil: Date?

    public init(token: @escaping TokenProvider, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    public var isSignedIn: Bool { token() != nil }

    // MARK: Status

    public struct Key: Hashable, Sendable {
        public var owner: String
        public var repo: String
        public var number: Int
        public init(owner: String, repo: String, number: Int) { self.owner = owner; self.repo = repo; self.number = number }
    }

    /// One query for every PR and issue open in tabs.
    public func statuses(for keys: [Key]) async throws -> [Key: GitHubStatus] {
        guard !keys.isEmpty else { return [:] }
        let unique = Array(Set(keys)).prefix(50)
        var variables: [String: Any] = [:]
        var definitions: [String] = []
        var fields: [String] = []
        for (index, key) in unique.enumerated() {
            definitions.append("$o\(index): String!, $r\(index): String!, $n\(index): Int!")
            variables["o\(index)"] = key.owner
            variables["r\(index)"] = key.repo
            variables["n\(index)"] = key.number
            fields.append("i\(index): repository(owner: $o\(index), name: $r\(index)) { issueOrPullRequest(number: $n\(index)) { ...Item } }")
        }
        let query = "query(\(definitions.joined(separator: ", "))) {\n\(fields.joined(separator: "\n"))\n}\n" + Self.itemFragment
        let data = try await graphQL(query, variables: variables)
        var result: [Key: GitHubStatus] = [:]
        for (index, key) in unique.enumerated() {
            let node = (data["i\(index)"] as? [String: Any])?["issueOrPullRequest"] as? [String: Any]
            if let node, let status = Self.decodeStatus(node) { result[key] = status }
        }
        return result
    }

    static let itemFragment = """
    fragment Item on IssueOrPullRequest {
      __typename
      ... on PullRequest {
        title state isDraft reviewDecision headRefName baseRefName mergeable
        commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 50) { nodes {
          __typename
          ... on CheckRun { name conclusion status detailsUrl }
          ... on StatusContext { context state targetUrl }
        } } } } } }
        reviewRequests(first: 10) { nodes { requestedReviewer { ... on User { login } ... on Team { name } } } }
      }
      ... on Issue { title state stateReason }
    }
    """

    static func decodeStatus(_ node: [String: Any]) -> GitHubStatus? {
        guard let typename = node["__typename"] as? String, let title = node["title"] as? String,
              let state = node["state"] as? String else { return nil }
        if typename == "Issue" {
            let closed = state == "CLOSED"
            return GitHubStatus(title: title,
                                state: closed ? .issueClosed(completed: (node["stateReason"] as? String) != "NOT_PLANNED") : .issueOpen,
                                checks: .none, checkRuns: [], reviewers: [])
        }
        let prState: GitHubStatus.State = switch state {
        case "MERGED": .merged
        case "CLOSED": .closed
        default: (node["isDraft"] as? Bool) == true ? .draft : .open
        }
        let rollup = (((node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["commit"] as? [String: Any])?["statusCheckRollup"] as? [String: Any]
        let contexts = ((rollup?["contexts"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        let runs: [GitHubStatus.Check] = contexts.compactMap { context in
            if let name = context["name"] as? String {
                let conclusion = context["conclusion"] as? String
                let result: GitHubStatus.Checks = switch conclusion {
                case "SUCCESS", "NEUTRAL", "SKIPPED": .passing
                case nil: .pending
                default: .failing
                }
                return .init(name: name, result: result, url: (context["detailsUrl"] as? String).flatMap(URL.init(string:)))
            }
            if let name = context["context"] as? String {
                return .init(name: name, result: rollupState(context["state"] as? String),
                             url: (context["targetUrl"] as? String).flatMap(URL.init(string:)))
            }
            return nil
        }
        let reviewers = (((node["reviewRequests"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []).compactMap { request in
            let reviewer = request["requestedReviewer"] as? [String: Any]
            return (reviewer?["login"] as? String) ?? (reviewer?["name"] as? String)
        }
        return GitHubStatus(title: title, state: prState, checks: rollupState(rollup?["state"] as? String),
                            checkRuns: runs.sorted { order($0.result) < order($1.result) },
                            reviewDecision: node["reviewDecision"] as? String,
                            headRef: node["headRefName"] as? String, baseRef: node["baseRefName"] as? String,
                            mergeable: node["mergeable"] as? String, reviewers: reviewers)
    }

    private static func rollupState(_ state: String?) -> GitHubStatus.Checks {
        switch state {
        case "SUCCESS": .passing
        case "FAILURE", "ERROR": .failing
        case "PENDING", "EXPECTED": .pending
        default: .none
        }
    }

    /// Failing first, then pending, then passing.
    private static func order(_ result: GitHubStatus.Checks) -> Int {
        switch result {
        case .failing: 0
        case .pending: 1
        case .passing: 2
        case .none: 3
        }
    }

    // MARK: Review queue

    public func reviewQueue() async throws -> [GitHubQueueItem] {
        let query = """
        query {
          review: search(query: "is:open is:pr review-requested:@me archived:false", type: ISSUE, first: 30) {
            nodes { ... on PullRequest { number title url repository { nameWithOwner } } } }
          mine: search(query: "is:open is:pr author:@me archived:false", type: ISSUE, first: 30) {
            nodes { ... on PullRequest { number title url repository { nameWithOwner }
              commits(last: 1) { nodes { commit { statusCheckRollup { state } } } } } } }
        }
        """
        return Self.decodeQueue(try await graphQL(query, variables: [:]))
    }

    static func decodeQueue(_ data: [String: Any]) -> [GitHubQueueItem] {
        func items(_ key: String, reason: GitHubQueueItem.Reason, filter: ([String: Any]) -> Bool) -> [GitHubQueueItem] {
            (((data[key] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []).compactMap { node in
                guard filter(node), let number = node["number"] as? Int, let title = node["title"] as? String,
                      let url = (node["url"] as? String).flatMap(URL.init(string:)),
                      let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String else { return nil }
                return GitHubQueueItem(repo: repo, number: number, title: title, url: url, reason: reason)
            }
        }
        let failing: ([String: Any]) -> Bool = { node in
            let state = ((((node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["commit"] as? [String: Any])?["statusCheckRollup"] as? [String: Any])?["state"] as? String
            return state == "FAILURE" || state == "ERROR"
        }
        return items("review", reason: .reviewRequested) { _ in true } + items("mine", reason: .failingChecks, filter: failing)
    }

    // MARK: Account

    public func viewer() async throws -> GitHubAccount {
        let data = try await graphQL("query { viewer { login name avatarUrl } }", variables: [:])
        guard let account = Self.decodeViewer(data) else { throw Failure.graphQL("No viewer in response") }
        return account
    }

    static func decodeViewer(_ data: [String: Any]) -> GitHubAccount? {
        guard let viewer = data["viewer"] as? [String: Any], let login = viewer["login"] as? String else { return nil }
        let name = (viewer["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        return GitHubAccount(login: login, name: name, avatarURL: (viewer["avatarUrl"] as? String).flatMap(URL.init(string:)))
    }

    // MARK: Search and refs

    public func searchRepositories(_ text: String) async throws -> [GitHubRepository] {
        let query = """
        query($q: String!) { search(query: $q, type: REPOSITORY, first: 5) {
          nodes { ... on Repository { nameWithOwner description url } } } }
        """
        let data = try await graphQL(query, variables: ["q": "\(text) in:name"])
        return (((data["search"] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []).compactMap { node in
            guard let name = node["nameWithOwner"] as? String, let url = (node["url"] as? String).flatMap(URL.init(string:)) else { return nil }
            return GitHubRepository(nameWithOwner: name, description: node["description"] as? String, url: url)
        }
    }

    /// Resolves a branch or tag to its commit SHA. Works signed out for public repositories.
    public func resolveSHA(owner: String, repo: String, ref: String) async throws -> String {
        let encodedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(owner)/\(repo)/commits/\(encodedRef)")!)
        request.setValue("application/vnd.github.sha", forHTTPHeaderField: "Accept")
        if let token = token() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let sha = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              sha.count == 40, sha.allSatisfy(\.isHexDigit) else { throw URLError(.badServerResponse) }
        return sha
    }

    // MARK: Transport

    public enum Failure: Error, Sendable { case signedOut, rateLimited(until: Date), http(Int), graphQL(String) }

    private func graphQL(_ query: String, variables: [String: Any]) async throws -> [String: Any] {
        guard let token = token() else { throw Failure.signedOut }
        if let until = rateLimitedUntil, until > Date() { throw Failure.rateLimited(until: until) }
        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        if http?.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0",
           let reset = http?.value(forHTTPHeaderField: "x-ratelimit-reset").flatMap(TimeInterval.init) {
            rateLimitedUntil = Date(timeIntervalSince1970: reset)
        }
        guard let status = http?.statusCode, status == 200 else { throw Failure.http(http?.statusCode ?? 0) }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        if let errors = json?["errors"] as? [[String: Any]], json?["data"] == nil {
            throw Failure.graphQL(errors.compactMap { $0["message"] as? String }.joined(separator: "; "))
        }
        return json?["data"] as? [String: Any] ?? [:]
    }
}
