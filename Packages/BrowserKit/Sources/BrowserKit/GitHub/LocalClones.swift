import Foundation

/// Finds local clones of GitHub repositories under a code folder, for "Open in Editor".
public struct LocalClones: Sendable {
    /// "owner/repo" (lowercased) → clone directory.
    public private(set) var clones: [String: URL] = [:]

    public init(clones: [String: URL] = [:]) { self.clones = clones }

    /// Scans `root` up to `depth` levels for `.git/config` files. Skips dependency folders.
    public static func scan(root: URL, depth: Int = 3) -> LocalClones {
        var found: [String: URL] = [:]
        let skipped: Set<String> = ["node_modules", ".build", "build", "DerivedData", "Pods", "vendor", "target", ".git"]
        func visit(_ directory: URL, level: Int) {
            let config = directory.appendingPathComponent(".git/config")
            if let text = try? String(contentsOf: config, encoding: .utf8) {
                for slug in remoteSlugs(inGitConfig: text) where found[slug] == nil { found[slug] = directory }
                return
            }
            guard level < depth, let children = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return }
            for child in children where !skipped.contains(child.lastPathComponent) {
                if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true { visit(child, level: level + 1) }
            }
        }
        visit(root, level: 0)
        return LocalClones(clones: found)
    }

    /// GitHub remotes in a `.git/config`, as lowercased "owner/repo".
    static func remoteSlugs(inGitConfig text: String) -> [String] {
        text.split(separator: "\n").compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("url") , let equals = trimmed.firstIndex(of: "=") else { return nil }
            return slug(fromRemote: trimmed[trimmed.index(after: equals)...].trimmingCharacters(in: .whitespaces))
        }
    }

    static func slug(fromRemote remote: String) -> String? {
        var path: Substring
        if let range = remote.range(of: "github.com:") {           // git@github.com:owner/repo.git
            path = remote[range.upperBound...]
        } else if let range = remote.range(of: "github.com/") {    // https:// or ssh://git@github.com/owner/repo
            path = remote[range.upperBound...]
        } else {
            return nil
        }
        if path.hasSuffix(".git") { path = path.dropLast(4) }
        let parts = path.split(separator: "/")
        guard parts.count == 2 else { return nil }
        return "\(parts[0])/\(parts[1])".lowercased()
    }

    public func clone(for github: GitHubURL) -> URL? {
        clones[github.slug.lowercased()]
    }

    /// The local file for a blob or tree URL, refusing any path that would escape the clone.
    public func file(for github: GitHubURL) -> (url: URL, line: Int?)? {
        guard let root = clone(for: github) else { return nil }
        let relative: String
        var line: Int?
        switch github.kind {
        case .blob(_, let path, let lines):
            relative = path
            line = lines?.lowerBound
        case .tree(_, let path):
            relative = path
        default:
            return (root, nil)
        }
        // Repository paths come from a URL the page controls; refuse anything that climbs out.
        let segments = relative.split(separator: "/", omittingEmptySubsequences: false)
        guard !relative.hasPrefix("/"), !segments.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        return (root.appendingPathComponent(relative), line)
    }
}

public enum CodeEditor: String, CaseIterable, Identifiable, Sendable {
    case vscode, cursor, zed, xcode

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .vscode: "Visual Studio Code"
        case .cursor: "Cursor"
        case .zed: "Zed"
        case .xcode: "Xcode"
        }
    }

    public var bundleIdentifier: String {
        switch self {
        case .vscode: "com.microsoft.VSCode"
        case .cursor: "com.todesktop.230313mzl4w4u92"
        case .zed: "dev.zed.Zed"
        case .xcode: "com.apple.dt.Xcode"
        }
    }

    /// URL that opens `file` at `line`; nil for editors opened as a plain document (Xcode).
    public func url(for file: URL, line: Int?) -> URL? {
        let path = file.path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? file.path
        let suffix = line.map { ":\($0)" } ?? ""
        switch self {
        case .vscode: return URL(string: "vscode://file\(path)\(suffix)")
        case .cursor: return URL(string: "cursor://file\(path)\(suffix)")
        case .zed: return URL(string: "zed://file\(path)\(suffix)")
        case .xcode: return nil
        }
    }
}
