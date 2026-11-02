import Foundation

/// Live state of a pull request or issue, as shown in the tab strip and context popover.
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
    /// Where the item leads: the pull request, or its Checks tab when the checks are what's waiting.
    public var destination: URL { reason == .failingChecks ? url.appending(path: "checks") : url }
}

/// An open pull request on the home page's Reviews: one waiting on your review, or one of yours.
public struct GitHubPull: Equatable, Sendable, Identifiable {
    public var repo: String
    public var number: Int
    public var title: String
    public var url: URL
    public var author: String?
    public var authorAvatarURL: URL?
    /// Opened by an app, such as Dependabot or Renovate, rather than a person.
    public var isBot: Bool
    public var isDraft: Bool
    public var createdAt: Date?
    public var updatedAt: Date?
    public var additions: Int
    public var deletions: Int
    public var headRef: String?
    public var baseRef: String?
    public var reviewDecision: String?
    public var checks: GitHubStatus.Checks
    /// The review was asked of one of your teams rather than of you.
    public var isTeamRequest = false
    /// The first team asked to review, when GitHub lists one.
    public var requestedTeam: String?
    /// The description as the author wrote it (Markdown), cut to `bodyLimit` characters.
    public var body: String?
    public var changedFiles: Int
    /// Paths of the first files the pull request changes, up to 100.
    public var files: [String]
    public var labels: [String]
    /// Comments and review comments together.
    public var commentCount: Int
    /// Each reviewer's latest approval or request for changes.
    public var reviews: [Review]
    /// People and teams asked to review who haven't yet.
    public var pendingReviewers: [String]
    /// The description's first paragraph of prose and the areas the files fall in, worked out
    /// once from the body and files given at init, so rows never parse while they draw.
    public let excerpt: String?
    public let areas: [PullContext.Area]
    public var id: String { "\(repo)#\(number)" }

    public struct Review: Equatable, Sendable {
        public enum State: Equatable, Sendable { case approved, changesRequested, commented }
        public var login: String
        public var state: State
        public init(login: String, state: State) { self.login = login; self.state = state }
    }

    public static let bodyLimit = 4000

    public var approvals: Int { reviews.count { $0.state == .approved } }
    public var changeRequests: Int { reviews.count { $0.state == .changesRequested } }

    public init(repo: String, number: Int, title: String, url: URL, author: String? = nil, authorAvatarURL: URL? = nil,
                isBot: Bool = false, isDraft: Bool = false, createdAt: Date? = nil, updatedAt: Date? = nil, additions: Int = 0, deletions: Int = 0,
                headRef: String? = nil, baseRef: String? = nil, reviewDecision: String? = nil, checks: GitHubStatus.Checks = .none,
                isTeamRequest: Bool = false, requestedTeam: String? = nil, body: String? = nil, changedFiles: Int = 0,
                files: [String] = [], labels: [String] = [], commentCount: Int = 0, reviews: [Review] = [], pendingReviewers: [String] = []) {
        self.repo = repo
        self.number = number
        self.title = title
        self.url = url
        self.author = author
        self.authorAvatarURL = authorAvatarURL
        self.isBot = isBot
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.additions = additions
        self.deletions = deletions
        self.headRef = headRef
        self.baseRef = baseRef
        self.reviewDecision = reviewDecision
        self.checks = checks
        self.isTeamRequest = isTeamRequest
        self.requestedTeam = requestedTeam
        self.body = body
        self.changedFiles = changedFiles
        self.files = files
        self.labels = labels
        self.commentCount = commentCount
        self.reviews = reviews
        self.pendingReviewers = pendingReviewers
        excerpt = PullContext.excerpt(markdown: body)
        areas = PullContext.areas(paths: files)
    }
}

/// Everything the review queue and the home page's Reviews show, from one request.
public struct GitHubPulls: Equatable, Sendable {
    /// Open pull requests asking for your review, directly or through a team.
    public var reviewRequested: [GitHubPull] = []
    /// Your own open pull requests.
    public var mine: [GitHubPull] = []
    /// How many each search matched; more than were fetched when the list is cut short.
    public var reviewRequestedTotal = 0
    public var mineTotal = 0

    public init(reviewRequested: [GitHubPull] = [], mine: [GitHubPull] = [], reviewRequestedTotal: Int = 0, mineTotal: Int = 0) {
        self.reviewRequested = reviewRequested
        self.mine = mine
        self.reviewRequestedTotal = reviewRequestedTotal
        self.mineTotal = mineTotal
    }

    /// The toolbar's review queue: review requests, then your pull requests with failing checks.
    public var queue: [GitHubQueueItem] {
        reviewRequested.map { GitHubQueueItem(repo: $0.repo, number: $0.number, title: $0.title, url: $0.url, reason: .reviewRequested) }
            + mine.filter { $0.checks == .failing }
            .map { GitHubQueueItem(repo: $0.repo, number: $0.number, title: $0.title, url: $0.url, reason: .failingChecks) }
    }
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

    /// Review requests (direct and through teams) and your own open pull requests, in one request.
    /// The direct search only tells the two kinds of request apart.
    public func pulls() async throws -> GitHubPulls {
        let query = """
        query {
          direct: search(query: "is:open is:pr user-review-requested:@me archived:false", type: ISSUE, first: \(Self.pullLimit)) {
            nodes { ... on PullRequest { number repository { nameWithOwner } } } }
          review: search(query: "is:open is:pr review-requested:@me archived:false sort:updated-desc", type: ISSUE, first: \(Self.pullLimit)) {
            issueCount nodes { ...Pull } }
          mine: search(query: "is:open is:pr author:@me archived:false sort:updated-desc", type: ISSUE, first: \(Self.pullLimit)) {
            issueCount nodes { ...Pull } }
        }
        fragment Pull on PullRequest {
          number title url isDraft createdAt updatedAt additions deletions headRefName baseRefName reviewDecision
          body changedFiles totalCommentsCount
          repository { nameWithOwner }
          author { __typename login avatarUrl(size: 40) }
          commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
          reviewRequests(first: 10) { nodes { requestedReviewer { __typename ... on User { login } ... on Team { name } } } }
          files(first: 100) { nodes { path } }
          labels(first: 10) { nodes { name } }
          latestOpinionatedReviews(first: 10) { nodes { state author { login } } }
        }
        """
        return Self.decodePulls(try await graphQL(query, variables: [:]))
    }

    public static let pullLimit = 50

    static func decodePulls(_ data: [String: Any]) -> GitHubPulls {
        func nodes(_ key: String) -> [[String: Any]] {
            ((data[key] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? []
        }
        func total(_ key: String) -> Int { ((data[key] as? [String: Any])?["issueCount"] as? Int) ?? 0 }
        let direct = Set(nodes("direct").compactMap { node -> String? in
            guard let number = node["number"] as? Int,
                  let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String else { return nil }
            return "\(repo)#\(number)"
        })
        var review = nodes("review").compactMap(decodePull)
        for index in review.indices where !direct.contains(review[index].id) {
            review[index].isTeamRequest = true
        }
        let mine = nodes("mine").compactMap(decodePull)
        return GitHubPulls(reviewRequested: review, mine: mine,
                           reviewRequestedTotal: max(total("review"), review.count), mineTotal: max(total("mine"), mine.count))
    }

    static func decodePull(_ node: [String: Any]) -> GitHubPull? {
        guard let number = node["number"] as? Int, let title = node["title"] as? String,
              let url = (node["url"] as? String).flatMap(URL.init(string:)),
              let repo = (node["repository"] as? [String: Any])?["nameWithOwner"] as? String else { return nil }
        let author = node["author"] as? [String: Any]
        let rollup = ((((node["commits"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["commit"] as? [String: Any])?["statusCheckRollup"] as? [String: Any])?["state"] as? String
        func list(_ key: String) -> [[String: Any]] { ((node[key] as? [String: Any])?["nodes"] as? [[String: Any]]) ?? [] }
        let requested = list("reviewRequests").compactMap { $0["requestedReviewer"] as? [String: Any] }
        let team = requested.first { $0["__typename"] as? String == "Team" }?["name"] as? String
        let reviews: [GitHubPull.Review] = list("latestOpinionatedReviews").compactMap { review in
            guard let login = (review["author"] as? [String: Any])?["login"] as? String else { return nil }
            let state: GitHubPull.Review.State? = switch review["state"] as? String {
            case "APPROVED": .approved
            case "CHANGES_REQUESTED": .changesRequested
            case "COMMENTED": .commented
            default: nil
            }
            return state.map { GitHubPull.Review(login: login, state: $0) }
        }
        let body = (node["body"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(GitHubPull.bodyLimit)) }
        func date(_ key: String) -> Date? { (node[key] as? String).flatMap { try? Date($0, strategy: .iso8601) } }
        return GitHubPull(repo: repo, number: number, title: title, url: url,
                          author: author?["login"] as? String,
                          authorAvatarURL: (author?["avatarUrl"] as? String).flatMap(URL.init(string:)),
                          isBot: author?["__typename"] as? String == "Bot",
                          isDraft: node["isDraft"] as? Bool ?? false,
                          createdAt: date("createdAt"), updatedAt: date("updatedAt"),
                          additions: node["additions"] as? Int ?? 0, deletions: node["deletions"] as? Int ?? 0,
                          headRef: node["headRefName"] as? String, baseRef: node["baseRefName"] as? String,
                          reviewDecision: node["reviewDecision"] as? String,
                          checks: rollupState(rollup), requestedTeam: team, body: body,
                          changedFiles: node["changedFiles"] as? Int ?? 0,
                          files: list("files").compactMap { $0["path"] as? String },
                          labels: list("labels").compactMap { $0["name"] as? String },
                          commentCount: node["totalCommentsCount"] as? Int ?? 0,
                          reviews: reviews,
                          pendingReviewers: requested.compactMap { ($0["login"] as? String) ?? ($0["name"] as? String) })
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
