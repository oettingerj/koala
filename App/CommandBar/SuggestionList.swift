import BrowserKit
import SwiftUI

/// Rows shared by the command bar and the address field dropdown.
struct SuggestionList: View {
    @Bindable var model: SuggestionModel
    var onActivate: (Suggestion) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                ForEach(Array(model.rows.enumerated()), id: \.element.id) { index, row in
                    SuggestionRow(row: row, icon: row.iconHost.flatMap { model.icons[$0] },
                                  isSelected: index == model.selectedIndex)
                        .id(row.id)
                        .contentShape(Rectangle())
                        .onTapGesture { onActivate(row) }
                        .onHover { inside in if inside { model.selectedIndex = index } }
                }
            }
            .padding(6)
            .onChange(of: model.selectedIndex) { _, index in
                if model.rows.indices.contains(index) { proxy.scrollTo(model.rows[index].id) }
            }
        }
    }
}

struct SuggestionRow: View {
    let row: Suggestion
    let icon: NSImage?
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            iconView
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.title)
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular))
                    .foregroundStyle(Color(nsColor: Theme.textPrimary))
                    .lineLimit(1)
                if let url = subtitleURL {
                    // Same reading as the address field: host first, path quieter.
                    (Text(url.host).foregroundStyle(Color(nsColor: Theme.textSecondary))
                        + Text(url.remainder).foregroundStyle(Color(nsColor: Theme.textTertiary)))
                        .font(.system(size: 11, design: .monospaced))
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
        .frame(height: 40)
        .background(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .fill(isSelected ? Color(nsColor: Theme.hoverFill) : .clear)
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var isURL: Bool { [.history, .bookmark, .tab, .github].contains(row.kind) }

    private var subtitleText: String? {
        switch row.kind {
        case .navigate, .search, .web, .command: nil
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
        case .navigate: "Open"
        default: nil
        }
    }

    @ViewBuilder private var iconView: some View {
        if let icon {
            Image(nsImage: icon).resizable().interpolation(.high)
        } else {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
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
        }
    }
}
