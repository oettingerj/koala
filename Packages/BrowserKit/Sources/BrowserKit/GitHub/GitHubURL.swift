import Foundation

/// What a github.com URL points at. Pure parsing; drives tab badges, the context chip,
/// permalinks, and open-in-editor.
public struct GitHubURL: Equatable, Hashable, Sendable {
    public enum Kind: Equatable, Hashable, Sendable {
        case repository
        case pullRequest(number: Int)
        case issue(number: Int)
        case commit(sha: String)
        /// A file at `ref`, optionally with a selected line range.
        case blob(ref: String, path: String, lines: ClosedRange<Int>?)
        case tree(ref: String, path: String)
        case compare(base: String, head: String)
        case actionsRun(id: Int)
        /// Any other page inside the repository (settings, releases, wiki…).
        case other(path: String)
    }

    public var owner: String
    public var repo: String
    public var kind: Kind

    public var slug: String { "\(owner)/\(repo)" }

    /// Pages of github.com that are not repositories.
    private static let reservedOwners: Set<String> = [
        "settings", "notifications", "login", "logout", "signup", "explore", "topics", "trending",
        "collections", "events", "marketplace", "pulls", "issues", "search", "sponsors", "orgs",
        "organizations", "new", "features", "pricing", "about", "codespaces", "copilot", "dashboard",
        "apps", "enterprise", "team", "security", "site", "contact", "readme", "stars", "watching",
    ]

    public init(owner: String, repo: String, kind: Kind) {
        self.owner = owner
        self.repo = repo
        self.kind = kind
    }

    public init?(_ url: URL?) {
        guard let url, let host = url.host()?.lowercased(), host == "github.com" || host == "www.github.com" else { return nil }
        var parts = url.path(percentEncoded: false).split(separator: "/").map(String.init)
        guard parts.count >= 2, !Self.reservedOwners.contains(parts[0].lowercased()) else { return nil }
        owner = parts.removeFirst()
        repo = parts.removeFirst()
        if repo.hasSuffix(".git") { repo.removeLast(4) }

        guard let section = parts.first else {
            kind = .repository
            return
        }
        let rest = Array(parts.dropFirst())
        switch section {
        case "pull" where rest.first.flatMap(Int.init) != nil:
            kind = .pullRequest(number: Int(rest[0])!)
        case "issues" where rest.first.flatMap(Int.init) != nil:
            kind = .issue(number: Int(rest[0])!)
        case "commit" where !rest.isEmpty:
            kind = .commit(sha: rest[0])
        case "blob" where rest.count >= 2:
            kind = .blob(ref: rest[0], path: rest.dropFirst().joined(separator: "/"), lines: Self.lines(url.fragment))
        case "tree" where !rest.isEmpty:
            kind = .tree(ref: rest[0], path: rest.dropFirst().joined(separator: "/"))
        case "compare" where !rest.isEmpty:
            let spec = rest.joined(separator: "/")
            let sides = spec.components(separatedBy: "...")
            kind = sides.count == 2 ? .compare(base: sides[0], head: sides[1]) : .other(path: "compare/" + spec)
        case "actions" where rest.count >= 2 && rest[0] == "runs" && Int(rest[1]) != nil:
            kind = .actionsRun(id: Int(rest[1])!)
        default:
            kind = .other(path: parts.joined(separator: "/"))
        }
    }

    /// "L10" or "L10-L20" (also "L10C3-L20C8") from a URL fragment.
    static func lines(_ fragment: String?) -> ClosedRange<Int>? {
        guard let fragment, fragment.hasPrefix("L") else { return nil }
        let numbers = fragment.split(separator: "-").compactMap { part -> Int? in
            let digits = part.drop { $0 == "L" }.prefix { $0.isNumber }
            return Int(digits)
        }
        guard let first = numbers.first else { return nil }
        let last = numbers.count > 1 ? numbers[1] : first
        return min(first, last)...max(first, last)
    }

    public var number: Int? {
        switch kind {
        case .pullRequest(let number), .issue(let number): number
        default: nil
        }
    }

    /// Short label for the context chip: "swiftlang/swift · #123".
    public var label: String {
        switch kind {
        case .pullRequest(let n), .issue(let n): "\(slug) · #\(n)"
        case .commit(let sha): "\(slug) · \(sha.prefix(7))"
        case .blob(_, let path, _), .tree(_, let path): path.isEmpty ? slug : "\(slug) · \(path.split(separator: "/").last ?? "")"
        case .actionsRun(let id): "\(slug) · run \(id)"
        default: slug
        }
    }

    /// `https://github.com/owner/repo/blob/<sha>/path#L1-L2` for a blob at a resolved commit.
    public func permalink(sha: String) -> URL? {
        guard case .blob(_, let path, let lines) = kind else { return nil }
        let encoded = path.split(separator: "/").map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        var string = "https://github.com/\(owner)/\(repo)/blob/\(sha)/\(encoded)"
        if let lines { string += lines.count == 1 ? "#L\(lines.lowerBound)" : "#L\(lines.lowerBound)-L\(lines.upperBound)" }
        return URL(string: string)
    }

    /// The PR or issue title from GitHub's page title, which reads
    /// "Title by author · Pull Request #12 · owner/repo".
    public static func itemTitle(fromPageTitle pageTitle: String) -> String {
        var title = pageTitle
        for marker in [" · Pull Request #", " · Issue #"] {
            if let range = title.range(of: marker) { title = String(title[..<range.lowerBound]) }
        }
        if let by = title.range(of: " by ", options: .backwards) { title = String(title[..<by.lowerBound]) }
        return title.trimmingCharacters(in: .whitespaces)
    }

    /// Parses shorthand typed into the command bar: "owner/repo#123".
    public static func shorthand(_ text: String) -> URL? {
        let pattern = /^([A-Za-z0-9-]+)\/([A-Za-z0-9._-]+)#(\d+)$/
        guard let match = text.wholeMatch(of: pattern) else { return nil }
        // GitHub redirects /pull/N to /issues/N (and back) as needed.
        return URL(string: "https://github.com/\(match.1)/\(match.2)/pull/\(match.3)")
    }
}
