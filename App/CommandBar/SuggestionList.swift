import BrowserKit
import SwiftUI

/// Rows shared by the command bar and the address field dropdown, grouped into sections, with
/// an optional preview of the highlighted row beside them.
struct SuggestionList: View {
    @Bindable var model: SuggestionModel
    var showsPreview = false
    /// Passed to the preview's key hints.
    var opensInNewTab = false
    var onActivate: (Suggestion) -> Void

    var body: some View {
        HStack(spacing: 0) {
            rows
            if showsPreview, let row = model.selected {
                Rectangle().fill(Color(nsColor: Theme.hairline)).frame(width: 1)
                SuggestionPreview(row: row, icon: icon(for: row), facts: model.facts, opensInNewTab: opensInNewTab)
                    .frame(width: SuggestionMetrics.previewWidth)
            }
        }
    }

    private var rows: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                        if model.startsSection(at: index), let title = row.section.title {
                            SectionHeader(title: title).id(Self.headerID(row))
                        }
                        SuggestionRow(row: row, icon: icon(for: row), isSelected: index == model.selectedIndex)
                            .id(row.id)
                            .contentShape(Rectangle())
                            .onTapGesture { onActivate(row) }
                            .onHover { inside in if inside { model.hover(at: index) } }
                    }
                }
                .padding(SuggestionMetrics.listInset)
            }
            .scrollBounceBehavior(.basedOnSize)
            .onChange(of: model.selectedIndex) { _, index in
                guard model.rows.indices.contains(index) else { return }
                let row = model.rows[index]
                // Reaching a section's first row brings its header into view too.
                proxy.scrollTo(model.startsSection(at: index) ? Self.headerID(row) : row.id)
                model.noteScrolled()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private static func headerID(_ row: Suggestion) -> String { "header:" + row.id }

    private func icon(for row: Suggestion) -> NSImage? {
        row.iconHost.flatMap { model.icons[$0] }
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color(nsColor: Theme.textTertiary))
            // Aligned with the row titles: row inset, icon, gap.
            .padding(.leading, 36)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, minHeight: SuggestionMetrics.headerHeight, maxHeight: SuggestionMetrics.headerHeight,
                   alignment: .bottomLeading)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SuggestionRow: View {
    let row: Suggestion
    let icon: NSImage?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            SuggestionIcon(row: row, icon: icon, size: 16)
            if row.kind == .keyword, let keyword = row.keyword {
                SearchKeywordChip(keyword: keyword)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(Color(nsColor: Theme.textPrimary))
                    .lineLimit(1)
                if let url = subtitleURL {
                    // Same reading as the address field: host first, path quieter.
                    Text("\(Text(url.host).foregroundStyle(Color(nsColor: Theme.textSecondary)))\(Text(url.remainder).foregroundStyle(Color(nsColor: Theme.textTertiary)))")
                        .font(.mono(size: 11))
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if let subtitle = subtitleText {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Color(nsColor: Theme.textTertiary))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 11, weight: .regular).monospacedDigit())
                    .foregroundStyle(Color(nsColor: Theme.textTertiary))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: SuggestionMetrics.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(isSelected ? Color(nsColor: Theme.hoverFill) : .clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isURL: Bool { [.history, .bookmark, .tab, .github, .closed].contains(row.kind) }

    private var subtitleText: String? {
        switch row.kind {
        case .navigate, .search, .web, .command: nil
        // The chip already names the search.
        case .keyword: nil
        // URL rows show their URL only through `subtitleURL`, never as a raw string.
        case _ where isURL && row.subtitle.flatMap(URL.init(string:))?.scheme?.hasPrefix("http") == true: nil
        default: row.subtitle == row.title ? nil : row.subtitle
        }
    }

    /// URL subtitles drop the scheme and "www."; nil when the title already is the URL.
    private var subtitleURL: DisplayURL? {
        guard isURL, let subtitle = row.subtitle, let url = URL(string: subtitle), url.scheme?.hasPrefix("http") == true,
              let display = DisplayURL(url) else { return nil }
        let short = display.host + display.remainder
        if row.title == subtitle || row.title == short { return nil }
        return display
    }

    private var trailing: String? {
        switch row.kind {
        case .tab: "Switch to Tab"
        case .command: row.shortcut
        case .search: "Search"
        case .keyword: row.subtitle
        case .navigate: "Open"
        case .closed: "Reopen"
        case .history: row.lastVisitedAt.map(RelativeTime.short)
        default: nil
        }
    }
}

/// A row's icon: a GitHub pull request or issue's live state, else the favicon, else a symbol.
struct SuggestionIcon: View {
    let row: Suggestion
    let icon: NSImage?
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        content
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                if let color = status.flatMap({ GitHubStyle.color($0.checks) }) {
                    // The tab strip's checks dot, ringed in the panel surface.
                    Circle().fill(Color(nsColor: color))
                        .frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Color(nsColor: Theme.chromeSurface), lineWidth: 1.5).padding(-1.5))
                        .offset(x: 2, y: 2)
                }
            }
    }

    private var status: GitHubStatus? {
        GitHubService.shared.status(for: row.pageURL)
    }

    @ViewBuilder private var content: some View {
        if let status, let image = GitHubStyle.image(status.state, size: size * 0.75) {
            Image(nsImage: image)
        } else if let icon, let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua) {
            // Template-tinted when FaviconContrast turns a dark glyph light for dark chrome.
            Image(nsImage: FaviconContrast.displayImage(icon, for: appearance))
                .resizable()
                .interpolation(.high)
                .foregroundStyle(Color(nsColor: Theme.textSecondary))
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.75, weight: .medium))
                .foregroundStyle(Color(nsColor: row.kind == .command ? Theme.accent : Theme.textSecondary))
        }
    }

    private var symbol: String {
        switch row.kind {
        case .navigate: "globe"
        case .search, .web, .keyword: "magnifyingglass"
        case .tab: "square.on.square"
        case .command: "command"
        case .bookmark: "star"
        case .history: "clock"
        case .github: "arrow.triangle.pull"
        case .closed: "arrow.uturn.backward"
        }
    }
}

/// A keyword search's trigger word, in the Settings keyword chip's grammar.
struct SearchKeywordChip: View {
    let keyword: String

    var body: some View {
        Text(keyword)
            .font(.mono(size: 12, weight: .medium))
            .foregroundStyle(Color(nsColor: Theme.textPrimary))
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color(nsColor: Theme.fieldFill)))
    }
}

extension Suggestion {
    /// The keyword of a keyword search row ("kw:mdn" → "mdn").
    var keyword: String? {
        id.hasPrefix("kw:") ? String(id.dropFirst(3)) : nil
    }
}

/// Compact relative times for lists: "now", "5m", "3h", "Mon", "Mar 13".
enum RelativeTime {
    static func short(_ date: Date) -> String {
        short(date, now: Date())
    }

    static func short(_ date: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h ago" }
        if seconds < 6 * 86_400 { return date.formatted(.dateTime.weekday(.abbreviated)) }
        let sameYear = Calendar.current.isDate(date, equalTo: now, toGranularity: .year)
        return sameYear ? date.formatted(.dateTime.month(.abbreviated).day()) : date.formatted(.dateTime.month(.abbreviated).day().year())
    }
}
