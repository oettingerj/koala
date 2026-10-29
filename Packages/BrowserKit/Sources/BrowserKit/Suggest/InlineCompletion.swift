import Foundation

/// The address the field fills in ahead of the caret, as an omnibox does: "gith" shows
/// "github.com" with "ub.com" selected, so typing replaces it and Delete removes it.
public struct InlineCompletion: Equatable, Sendable {
    /// What the field shows: the typed text followed by the completed remainder.
    public var text: String
    /// The completed address, lowercased, without scheme or "www.". Identifies the
    /// completion while the user types through it, and when they reject it.
    public var key: String
    /// For a host: visits across the whole host, which the field's preview reports.
    public var hostVisits: Int?
    public var hostLastVisit: Date?
}

/// What the caller knows about the edit that asked for suggestions.
public struct CompletionContext: Sendable {
    /// False after a deletion, a paste, or an edit away from the end of the text.
    public var enabled: Bool
    /// The completion currently shown, kept while typing still matches it.
    public var current: String?
    /// Completions the user deleted during this edit, which never come back for it.
    public var suppressed: Set<String>

    public init(enabled: Bool = true, current: String? = nil, suppressed: Set<String> = []) {
        self.enabled = enabled
        self.current = current
        self.suppressed = suppressed
    }
}

/// Visited URLs sorted by their completion key, so a typed prefix finds its matches with one
/// binary search on every keystroke.
struct CompletionIndex {
    struct Entry {
        /// `display`, lowercased.
        var key: String
        /// Host and remainder as `DisplayURL` reads them: "github.com/swiftlang/swift".
        var display: String
        var url: URL
        var visits: Int
        var typed: Int
        var lastVisit: Date?
    }

    private(set) var entries: [Entry] = []

    init(_ entries: [Entry] = []) {
        var merged: [String: Entry] = [:]
        for entry in entries {
            // http/https and fragment variants are one address to the person typing it.
            if var existing = merged[entry.key] {
                if entry.visits > existing.visits { existing.url = entry.url }
                existing.visits += entry.visits
                existing.typed += entry.typed
                existing.lastVisit = [existing.lastVisit, entry.lastVisit].compactMap { $0 }.max()
                merged[entry.key] = existing
            } else {
                merged[entry.key] = entry
            }
        }
        self.entries = merged.values.sorted { $0.key < $1.key }
    }

    static func entry(url: URL, visits: Int, typed: Int, lastVisit: Date?) -> Entry? {
        guard let display = DisplayURL(url), url.scheme?.hasPrefix("http") == true else { return nil }
        let text = display.host + display.remainder
        return Entry(key: text.lowercased(), display: text, url: url, visits: visits, typed: typed, lastVisit: lastVisit)
    }

    mutating func noteVisit(url: URL, typed: Bool, at date: Date) {
        guard let new = Self.entry(url: url, visits: 1, typed: typed ? 1 : 0, lastVisit: date) else { return }
        let index = lowerBound(new.key)
        if entries.indices.contains(index), entries[index].key == new.key {
            entries[index].visits += 1
            if typed { entries[index].typed += 1 }
            entries[index].lastVisit = date
        } else {
            entries.insert(new, at: index)
        }
    }

    func entry(forKey key: String) -> Entry? {
        let index = lowerBound(key)
        return entries.indices.contains(index) && entries[index].key == key ? entries[index] : nil
    }

    /// Every entry whose key starts with `prefix`.
    func matches(_ prefix: String) -> ArraySlice<Entry> {
        let start = lowerBound(prefix)
        var end = start
        while end < entries.endIndex, entries[end].key.hasPrefix(prefix) { end += 1 }
        return entries[start..<end]
    }

    private func lowerBound(_ key: String) -> Int {
        var low = 0, high = entries.count
        while low < high {
            let mid = (low + high) / 2
            if entries[mid].key < key { low = mid + 1 } else { high = mid }
        }
        return low
    }
}

extension SuggestionEngine {
    struct CompletionCandidate {
        var key: String
        var display: String
        var url: URL
        /// Frecency of this address plus every visited address beneath it.
        var score: Double
        var visits: Int
        var typed: Int
        var lastVisit: Date?
    }

    /// The address the user most likely means by `raw`, or nil when no single address is
    /// likely enough to put words in their mouth.
    ///
    /// Before a "/" only hosts complete ("gi" → "github.com"); after one, whole addresses
    /// do ("github.com/sw" → "github.com/swiftlang/swift"). Candidates score by frecency:
    /// visits plus twice the typed visits, halved every 30 days. An address absorbs the scores
    /// of the pages beneath it, so the shorter, safer completion wins over any one child. The
    /// best candidate must show real intent (a host visited twice; an address typed once or
    /// visited three times), not have gone stale, and outscore its nearest unrelated rival by half again, or three
    /// times on a two-letter prefix.
    public func inlineCompletion(for raw: String, context: CompletionContext = .init(), now: Date = Date()) -> (InlineCompletion, URL)? {
        guard context.enabled, !raw.isEmpty, !raw.contains(where: \.isWhitespace) else { return nil }
        let input = Self.completionKey(raw)
        // A bare keyword is a search about to happen: "gh" waits for its space.
        guard input.count >= 2, !keywordSearches.contains(where: { $0.keyword.lowercased() == input }) else { return nil }

        let candidates = (input.contains("/") ? addressCandidates(input, now: now) : hostCandidates(input, now: now))
            .filter { $0.key != input && !context.suppressed.contains($0.key) }
        let chosen: CompletionCandidate
        if let current = context.current, current.hasPrefix(input), let kept = candidates.first(where: { $0.key == current }) {
            // Typing through the shown completion keeps it, so the field never flickers.
            chosen = kept
        } else {
            guard let best = Self.mostLikely(candidates, inputLength: input.count) else { return nil }
            chosen = best
        }
        let remainder = chosen.display.dropFirst(input.count)
        guard !remainder.isEmpty else { return nil }
        let isHost = !chosen.key.contains("/")
        return (InlineCompletion(text: raw + remainder, key: chosen.key, hostVisits: isHost ? chosen.visits : nil,
                                 hostLastVisit: isHost ? chosen.lastVisit : nil), chosen.url)
    }

    /// Lowercased, without scheme or "www.", as completion keys are stored.
    static func completionKey(_ raw: String) -> String {
        var text = raw.lowercased()
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        if text.hasPrefix("www.") { text.removeFirst(4) }
        return text
    }

    static func mostLikely(_ candidates: [CompletionCandidate], inputLength: Int) -> CompletionCandidate? {
        guard let best = candidates.max(by: { $0.score < $1.score }) else { return nil }
        let isHost = !best.key.contains("/")
        let intent = isHost ? best.visits + best.typed * 2 >= 2 : best.typed >= 1 || best.visits >= 3
        // Intent is in the counts; the score floor only drops what's gone stale (two visits two months ago).
        guard intent, best.score >= 1 else { return nil }
        let rival = candidates.filter { !related($0.key, best.key) }.map(\.score).max() ?? 0
        let margin = inputLength <= 2 ? 3.0 : 1.5
        return best.score >= rival * margin ? best : nil
    }

    /// Whether one address lies beneath the other ("a.com/x" and "a.com/x/y").
    static func related(_ a: String, _ b: String) -> Bool {
        isBeneath(a, b) || isBeneath(b, a) || a == b
    }

    static func isBeneath(_ child: String, _ parent: String) -> Bool {
        guard child.count > parent.count, child.hasPrefix(parent) else { return false }
        if parent.hasSuffix("/") { return true }
        let next = child[child.index(child.startIndex, offsetBy: parent.count)]
        return next == "/" || next == "?"
    }

    /// "a.com/x/y?q" → ["a.com/x/y", "a.com/x/", "a.com/x", "a.com/", "a.com"]: each address it lies beneath.
    static func parentKeys(of key: String) -> [String] {
        var parents: [String] = []
        var index = key.endIndex
        while let cut = key[..<index].lastIndex(where: { $0 == "/" || $0 == "?" }) {
            parents.append(String(key[...cut]))
            parents.append(String(key[..<cut]))
            index = cut
        }
        return parents.filter { $0 != key && !$0.isEmpty }
    }

    static func frecency(visits: Int, typed: Int, lastVisit: Date?, now: Date) -> Double {
        let age = lastVisit.map { max(0, now.timeIntervalSince($0)) / 86_400 } ?? 30
        return Double(visits + typed * 2) * pow(0.5, age / 30)
    }

    private func hostCandidates(_ input: String, now: Date) -> [CompletionCandidate] {
        knownHosts.filter { $0.host.hasPrefix(input) }.compactMap { host in
            // The recorded root page knows the scheme; else hosts with a port are local servers.
            let url = completionIndex.entry(forKey: host.host)?.url
                ?? URL(string: "\(host.host.contains(":") ? "http" : "https")://\(host.host)/")
            guard let url else { return nil }
            let typed = max(0, Int(host.weight) - host.visits) / 2
            return CompletionCandidate(key: host.host, display: host.host, url: url,
                                       score: Self.frecency(visits: host.visits, typed: typed, lastVisit: host.lastVisit, now: now),
                                       visits: host.visits, typed: typed, lastVisit: host.lastVisit)
        }
    }

    private func addressCandidates(_ input: String, now: Date) -> [CompletionCandidate] {
        let matches = completionIndex.matches(input).map { entry in
            (entry: entry, own: Self.frecency(visits: entry.visits, typed: entry.typed, lastVisit: entry.lastVisit, now: now))
        }
        // The strongest few, plus any visited parent of theirs, stand for the rest.
        let top = matches.sorted { $0.own > $1.own }.prefix(20)
        let parents = top.flatMap { Self.parentKeys(of: $0.entry.key) }.filter { $0.hasPrefix(input) }
            .compactMap { key in
                completionIndex.entry(forKey: key).map { entry in
                    (entry: entry, own: Self.frecency(visits: entry.visits, typed: entry.typed, lastVisit: entry.lastVisit, now: now))
                }
            }
        var seen = Set<String>()
        return (Array(top) + parents).filter { seen.insert($0.entry.key).inserted }.map { candidate in
            let beneath = matches.filter { Self.isBeneath($0.entry.key, candidate.entry.key) }
            return CompletionCandidate(key: candidate.entry.key, display: candidate.entry.display, url: candidate.entry.url,
                                       score: candidate.own + beneath.map(\.own).reduce(0, +),
                                       visits: candidate.entry.visits + beneath.map(\.entry.visits).reduce(0, +),
                                       typed: candidate.entry.typed + beneath.map(\.entry.typed).reduce(0, +),
                                       lastVisit: candidate.entry.lastVisit)
        }
    }
}
