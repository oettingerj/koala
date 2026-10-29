import BrowserKit
import SwiftUI

/// The pane beside the suggestion list: what the highlighted row is, why it's there, and what
/// Return does with it. Swaps instantly with the selection; nothing in it animates.
struct SuggestionPreview: View {
    let row: Suggestion
    let icon: NSImage?
    let facts: PreviewFacts?
    /// The command bar opens pages in a new tab on Return; the address field needs ⌘.
    var opensInNewTab = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            let facts = self.factRows
            if !facts.isEmpty {
                hairline
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 7) {
                    ForEach(facts) { fact in
                        GridRow {
                            Text(fact.label)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: Theme.textTertiary))
                                .gridColumnAlignment(.leading)
                            fact.value
                                .font(.system(size: 12))
                                .foregroundStyle(Color(nsColor: Theme.textPrimary))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .help(fact.help ?? "")
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .padding(14)
            }
            Spacer(minLength: 0)
            hairline
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var hairline: some View {
        Rectangle().fill(Color(nsColor: Theme.hairline)).frame(height: 1)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            SuggestionIcon(row: row, icon: icon, size: 20)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 4) {
                Text(row.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Theme.textPrimary))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let url = displayURL {
                    Text("\(Text(url.host).foregroundStyle(Color(nsColor: Theme.textSecondary)))\(Text(url.remainder).foregroundStyle(Color(nsColor: Theme.textTertiary)))")
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Color(nsColor: Theme.textSecondary))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    /// Where Return goes: the page itself, or the search a query becomes.
    private var displayURL: DisplayURL? {
        if let url = row.pageURL { return DisplayURL(url) }
        if case .open(let url) = row.action { return DisplayURL(url) }
        return nil
    }

    /// A line of prose the row carries that isn't a URL: a repository's description, or a
    /// queue item's reason.
    private var detail: String? {
        guard row.kind == .github, let subtitle = row.subtitle, URL(string: subtitle)?.scheme == nil else { return nil }
        return subtitle == row.title ? nil : subtitle
    }

    // MARK: Facts

    private struct Fact: Identifiable {
        let label: String
        let value: Text
        var help: String?
        var id: String { label }
    }

    private var factRows: [Fact] {
        var rows: [Fact] = []
        switch row.kind {
        case .command:
            if let path = row.menuPath { rows.append(Fact(label: "Menu", value: Text(path))) }
            if let shortcut = row.shortcut {
                rows.append(Fact(label: "Shortcut", value: Text(shortcut).font(.system(size: 13, weight: .medium).monospacedDigit())))
            }
            return rows
        case .keyword:
            if let subtitle = row.subtitle { rows.append(Fact(label: "Searches", value: Text(subtitle.replacingOccurrences(of: "Search ", with: "")))) }
            return rows
        case .search, .web:
            if let subtitle = row.subtitle { rows.append(Fact(label: "Searches", value: Text(subtitle.replacingOccurrences(of: "Search ", with: "")))) }
            return rows
        case .closed:
            rows.append(Fact(label: "Reopens", value: Text("With its back history")))
        default:
            break
        }
        let github = GitHubService.shared
        if let status = github.status(for: row.pageURL) {
            rows += githubFacts(status)
        } else if github.isStatusPending(for: row.pageURL) {
            // Held open while the state loads, so the grid doesn't shift when it arrives.
            rows.append(Fact(label: "State", value: Text(" ")))
            rows.append(Fact(label: "Checks", value: Text(" ")))
        }
        guard row.pageURL != nil, let facts, facts.id == row.id else { return rows }
        if row.kind == .tab {
            rows.append(Fact(label: "Tab", value: Text("Open")))
        } else if facts.isOpenInTab {
            rows.append(Fact(label: "Tab", value: Text("Also open in a tab")))
        }
        if let folder = facts.folderPath {
            rows.append(Fact(label: "Bookmark", value: Text(folder)))
        }
        if let count = facts.visitCount, let last = facts.lastVisitedAt {
            rows.append(Fact(label: "Visited",
                             value: Text("\(Text("\(count)×").font(.system(size: 12, design: .monospaced)))\(Text("  ·  \(RelativeTime.short(last))").foregroundStyle(Color(nsColor: Theme.textSecondary)))"),
                             help: last.formatted(date: .abbreviated, time: .shortened)))
        } else {
            // Holds the row while the visit count loads, so the pane doesn't grow under the pointer.
            rows.append(Fact(label: "Visited", value: Text(facts.visitsLoaded ? "Never" : " ")
                .foregroundStyle(Color(nsColor: Theme.textTertiary))))
        }
        return rows
    }

    private func githubFacts(_ status: GitHubStatus) -> [Fact] {
        var rows: [Fact] = []
        let glyph = GitHubStyle.glyph(status.state)
        let state = GitHubStyle.image(status.state, size: 11).map { Text("\(Image(nsImage: $0)) ") } ?? Text("")
        rows.append(Fact(label: "State", value: Text("\(state)\(Self.stateWord(status.state))"), help: glyph.label))
        if !status.checkRuns.isEmpty, let color = GitHubStyle.color(status.checks) {
            let passing = status.checkRuns.filter { $0.result == .passing }.count
            let failing = status.checkRuns.filter { $0.result == .failing }.count
            var words = "\(passing) of \(status.checkRuns.count) passing"
            if failing > 0 { words += ", \(failing) failing" }
            rows.append(Fact(label: "Checks", value: Text("\(Text(Image(systemName: "circle.fill")).font(.system(size: 7)).foregroundStyle(Color(nsColor: color)))\(Text("  " + words).font(.system(size: 12).monospacedDigit()))")))
        }
        if let head = status.headRef, let base = status.baseRef {
            rows.append(Fact(label: "Branch", value: Text("""
                \(Text(head).font(.system(size: 11, design: .monospaced)))\
                \(Text("  →  ").foregroundStyle(Color(nsColor: Theme.textTertiary)))\
                \(Text(base).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(nsColor: Theme.textSecondary)))
                """)))
        }
        let review = GitHubStyle.reviewSummary(status)
        if !review.isEmpty { rows.append(Fact(label: "Review", value: Text(review))) }
        return rows
    }

    private static func stateWord(_ state: GitHubStatus.State) -> String {
        switch state {
        case .open, .issueOpen: "Open"
        case .draft: "Draft"
        case .merged: "Merged"
        case .closed: "Closed"
        case .issueClosed(let completed): completed ? "Closed" : "Closed as not planned"
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↩", primaryVerb)
            if !opensInNewTab, case .open = row.action { hint("⌘↩", "New Tab") }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    private var primaryVerb: String {
        switch row.action {
        case .open: opensInNewTab ? "Open in New Tab" : "Open"
        case .switchToTab: "Switch to Tab"
        case .command: "Run"
        case .reopenClosed: "Reopen"
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(nsColor: Theme.textSecondary))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Color(nsColor: Theme.textTertiary))
        }
        .accessibilityElement(children: .combine)
    }
}
