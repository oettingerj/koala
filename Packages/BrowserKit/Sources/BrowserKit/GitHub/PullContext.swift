import CryptoKit
import Foundation

/// What a pull request is about, from what GitHub returns: a readable excerpt of its description,
/// the areas of the codebase it touches, and a fingerprint of the text a summary is made from.
public enum PullContext {
    // MARK: Excerpt

    /// The first paragraph of a description that reads as prose: template headings, checklists,
    /// HTML comments, images, code, tables, and "Closes #12" lines are skipped. Nil when nothing is left.
    public static func excerpt(markdown: String?) -> String? {
        guard var text = cleaned(markdown: markdown) else { return nil }
        text = text.replacing(/```[\s\S]*?(```|$)/, with: "\n\n")

        var paragraphs: [String] = []
        var current: [String] = []
        func flush() {
            if !current.isEmpty { paragraphs.append(current.joined(separator: " ")) }
            current = []
        }
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || isSkipped(line) {
                flush()
                continue
            }
            current.append(inline(line))
        }
        flush()
        return paragraphs
            .map { $0.replacing(/\s+/, with: " ").trimmingCharacters(in: .whitespaces) }
            .first { $0.split(separator: " ").count >= 4 }
    }

    /// The description without what a reader never sees on GitHub: HTML comments (where templates
    /// keep their instructions), images, and tags. Nil when nothing is left.
    public static func cleaned(markdown: String?) -> String? {
        guard var text = markdown else { return nil }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacing(/<!--[\s\S]*?-->/, with: "")
        text = text.replacing(/!\[[^\]]*\]\([^)]*\)/, with: "")
        text = text.replacing(/<[^>\n]+>/, with: "")
        text = text.replacing(/\n{3,}/, with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    private static func isSkipped(_ line: String) -> Bool {
        if line.hasPrefix("#") || line.hasPrefix("|") || line.hasPrefix(">") { return true }
        if line.wholeMatch(of: /[-*_=]{3,}/) != nil { return true }
        if line.firstMatch(of: /^[-*+]\s*\[[ xX]\]/) != nil { return true }
        // "Closes #12", "Fixes: org/repo#3", "Part of https://…": a reference, not prose.
        if line.firstMatch(of: /^(?i)(close[sd]?|fix(e[sd])?|resolve[sd]?|refs?|related( to)?|part of|see)\b/) != nil,
           line.contains("#") || line.contains("://"), line.split(separator: " ").count <= 5 {
            return true
        }
        // A line that is only a link or a URL, such as a ticket or preview link.
        if line.wholeMatch(of: /[-*+]?\s*(https?:\/\/\S+|\[[^\]]*\]\([^)]*\))/) != nil { return true }
        return false
    }

    /// Unwraps links, emphasis, and inline code, and drops a list marker.
    private static func inline(_ line: String) -> String {
        var line = line
        line = line.replacing(/^([-*+]|\d+[.)])\s+/, with: "")
        line = line.replacing(/\[([^\]]*)\]\([^)]*\)/) { String($0.output.1) }
        line = line.replacing(/(\*\*|__)(.+?)\1/) { String($0.output.2) }
        line = line.replacing(/(^|\s)[*_]([^*_\s][^*_]*?)[*_](?=[\s.,;:!?)]|$)/) { $0.output.1 + $0.output.2 }
        line = line.replacing(/`([^`]*)`/) { String($0.output.1) }
        return line
    }

    // MARK: Areas

    public struct Area: Equatable, Sendable {
        public var name: String
        public var count: Int
        public init(name: String, count: Int) { self.name = name; self.count = count }
    }

    /// The parts of the codebase a pull request touches, most files first. Directories every file
    /// shares are dropped, and so are `Sources` and `src`, so each name says where in the project
    /// the change is. Files at the top level go by their own names.
    public static func areas(paths: [String]) -> [Area] {
        let directories = paths.map { path -> [Substring] in
            Array(path.split(separator: "/").dropLast())
        }
        guard !directories.isEmpty else { return [] }
        // A shared prefix is dropped only while every file sits below it.
        // Keeps at least one directory per file, so a change inside one folder still names it.
        var shared = 0
        let deepest = max(0, (directories.map(\.count).min() ?? 0) - 1)
        if paths.count > 1, let first = directories.first {
            while shared < deepest, directories.allSatisfy({ $0[shared] == first[shared] }) {
                shared += 1
            }
        }
        var counts: [String: Int] = [:]
        var order: [String] = []
        for (path, components) in zip(paths, directories) {
            let meaningful = components.dropFirst(shared).filter { $0 != "Sources" && $0 != "src" }
            let name = meaningful.isEmpty
                ? (components.last.map(String.init) ?? path)
                : meaningful.prefix(2).joined(separator: "/")
            if counts[name] == nil { order.append(name) }
            counts[name, default: 0] += 1
        }
        return order.enumerated()
            .sorted { counts[$0.element]! != counts[$1.element]! ? counts[$0.element]! > counts[$1.element]! : $0.offset < $1.offset }
            .map { Area(name: $0.element, count: counts[$0.element]!) }
    }

    // MARK: Fingerprint

    /// Changes when the text a summary is made from changes, and is stable across launches.
    public static func fingerprint(_ pull: GitHubPull) -> String {
        let text = ([pull.title, pull.body ?? ""] + pull.files.prefix(40)).joined(separator: "\u{1F}")
        return SHA256.hash(data: Data(text.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
