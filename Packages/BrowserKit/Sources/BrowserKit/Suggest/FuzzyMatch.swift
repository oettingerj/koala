import Foundation

/// Scores how well a typed query matches a candidate string, for ranking command bar rows.
/// Prefix of the whole string beats prefix of a word, which beats a substring, which beats
/// an in-order subsequence ("gsw" → "GitHub swift"). nil means no match.
public enum FuzzyMatch {
    public static func score(_ query: String, in candidate: String) -> Double? {
        let q = query.lowercased()
        let c = candidate.lowercased()
        guard !q.isEmpty else { return 0 }
        if c.hasPrefix(q) { return 1.0 - lengthPenalty(q, c) }
        if let range = c.range(of: q) {
            let atWordStart = range.lowerBound == c.startIndex || !c[c.index(before: range.lowerBound)].isLetterOrNumber
            return (atWordStart ? 0.8 : 0.6) - lengthPenalty(q, c)
        }
        // Every query token is a word prefix somewhere: "swift form" → "swift-format".
        let tokens = q.split(whereSeparator: { !$0.isLetterOrNumber })
        if tokens.count > 1 {
            let words = c.split(whereSeparator: { !$0.isLetterOrNumber })
            if tokens.allSatisfy({ token in words.contains { $0.hasPrefix(token) } }) {
                return 0.7 - lengthPenalty(q, c)
            }
        }
        return subsequenceScore(q, c)
    }

    private static func lengthPenalty(_ q: String, _ c: String) -> Double {
        // Shorter candidates win ties: "Bookmarks" ranks over "Show Bookmarks Bar" for "book".
        min(0.15, Double(max(0, c.count - q.count)) * 0.002)
    }

    private static func subsequenceScore(_ q: String, _ c: String) -> Double? {
        var qi = q.startIndex
        var previousMatch: String.Index?
        var gaps = 0
        var index = c.startIndex
        while index < c.endIndex, qi < q.endIndex {
            if c[index] == q[qi] {
                if let previousMatch, c.index(after: previousMatch) != index { gaps += 1 }
                previousMatch = index
                qi = q.index(after: qi)
            }
            index = c.index(after: index)
        }
        guard qi == q.endIndex, q.count >= 2 else { return nil }
        return max(0.05, 0.4 - Double(gaps) * 0.05)
    }
}

private extension Character {
    var isLetterOrNumber: Bool { isLetter || isNumber }
}
