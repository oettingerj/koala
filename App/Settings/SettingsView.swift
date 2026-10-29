import AppKit
import BrowserKit
import SwiftUI

/// Settings that persist in user defaults and feed AppServices.
@MainActor
enum Preferences {
    /// Each engine with its search-as-you-type endpoint. Kagi's needs a signed-in session, so
    /// Koala sends Kagi users' typing nowhere.
    static let searchEngines: [(name: String, template: String, suggestions: String?)] = [
        ("Google", "https://www.google.com/search?q=%s", WebSuggestions.google),
        ("DuckDuckGo", "https://duckduckgo.com/?q=%s", "https://duckduckgo.com/ac/?q=%s&type=list"),
        ("Kagi", "https://kagi.com/search?q=%s", nil),
        ("Bing", "https://www.bing.com/search?q=%s", "https://api.bing.com/osjson.aspx?query=%s"),
    ]

    /// The chosen engine, or nil for a custom template.
    static var searchEngine: (name: String, template: String, suggestions: String?)? {
        searchEngines.first { $0.template == searchTemplate }
    }

    static var searchTemplate: String {
        get { UserDefaults.standard.string(forKey: "SearchTemplate") ?? AddressInput.defaultSearchTemplate }
        set { UserDefaults.standard.set(newValue, forKey: "SearchTemplate"); apply() }
    }

    static var webSuggestions: Bool {
        get { UserDefaults.standard.object(forKey: "WebSuggestions") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "WebSuggestions"); apply() }
    }

    static var keywordSearches: [KeywordSearch] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "KeywordSearches"),
                  let searches = try? JSONDecoder().decode([KeywordSearch].self, from: data) else { return KeywordSearch.defaults }
            return searches
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "KeywordSearches")
            apply()
        }
    }

    static func apply() {
        let engine = AppServices.shared.suggestions
        engine.searchTemplate = searchTemplate
        engine.searchName = searchEngine?.name ?? URL(string: searchTemplate).flatMap { DisplayURL($0)?.host } ?? "the Web"
        // Suggestions only ever go to the engine searches go to; a custom engine gets none.
        engine.web.endpoint = searchEngine?.suggestions
        engine.webSuggestionsEnabled = webSuggestions
        engine.keywordSearches = keywordSearches
    }
}

// MARK: Page

let settingsPrimary = Color(nsColor: Theme.textPrimary)
let settingsSecondary = Color(nsColor: Theme.textSecondary)
let settingsTertiary = Color(nsColor: Theme.textTertiary)
let settingsFail = Color(nsColor: Theme.fail)

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, github, keywords, extensions, data

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .github: "GitHub"
        case .keywords: "Search Keywords"
        case .extensions: "Extensions"
        case .data: "Browsing Data"
        }
    }

    var indexTitle: String { self == .keywords ? "Keywords" : title }

    var summary: String {
        switch self {
        case .general: "How the address field searches, and which browser opens links."
        case .github: "Pull request and CI status in tabs, and where Open in Editor finds your clones."
        case .keywords: "Type a keyword and a space in the address field or command bar to search that site."
        case .extensions: "Safari-compatible web extensions, including most Manifest V3 Chrome extensions."
        case .data: "Bring in bookmarks and history from another browser, or clear what Koala remembers."
        }
    }
}

/// One searchable row. Its section, title, detail, and terms are what the search field matches.
struct SettingEntry: Identifiable {
    let id: String
    let section: SettingsSection
    let title: String
    var detail: String?
    var terms: [String] = []

    var haystack: String { ([section.title, title, detail ?? ""] + terms).joined(separator: " ").lowercased() }
}

/// The search field's query. Like the command bar, every query word must start a word in the row's text,
/// so "pin" finds Pin to Toolbar but not "typing".
struct SettingsFilter {
    var query = ""

    var words: [String] { Self.words(in: query) }
    var isActive: Bool { !words.isEmpty }

    private static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "%" }.map(String.init)
    }

    func shows(_ entry: SettingEntry) -> Bool {
        let haystack = Self.words(in: entry.haystack)
        return words.allSatisfy { word in haystack.contains { $0.hasPrefix(word) } }
    }

    /// Sets the matched word starts in semibold at the text's own size, so a filtered row shows why it matched.
    func highlight(_ text: String, size: CGFloat, design: Font.Design = .default) -> AttributedString {
        var result = AttributedString(text)
        for word in words {
            var searchStart = text.startIndex
            while let range = text.range(of: word, options: .caseInsensitive, range: searchStart..<text.endIndex) {
                let startsWord = range.lowerBound == text.startIndex || !text[text.index(before: range.lowerBound)].isLetter
                    && !text[text.index(before: range.lowerBound)].isNumber
                if startsWord, let marked = Range(range, in: result) {
                    result[marked].font = .system(size: size, weight: .semibold, design: design)
                }
                searchStart = range.upperBound
            }
        }
        return result
    }
}

extension EnvironmentValues {
    @Entry var settingsFilter = SettingsFilter()
}

@MainActor
@Observable
final class SettingsModel {
    var query = ""
    /// Bumped to move focus to the search field (⌘F, ⌘, on an open Settings tab).
    var focusRequest = 0
    var visibleSection: SettingsSection? = .general

    var keywords = Preferences.keywordSearches.map { KeywordDraft(search: $0) } {
        // Only well-formed entries reach the suggestion engine: a single-word keyword and a template with %s.
        didSet { Preferences.keywordSearches = keywords.map(\.search).filter(KeywordDraft.isUsable) }
    }
    var expandedKeyword: KeywordDraft.ID?
    var focusesKeyword: KeywordDraft.ID?

    /// Appends an empty keyword, open for editing with its keyword field focused.
    func addKeyword() {
        let draft = KeywordDraft(search: KeywordSearch(keyword: "", name: "", template: "https://"))
        keywords.append(draft)
        expandedKeyword = draft.id
        focusesKeyword = draft.id
    }

    func entries(for section: SettingsSection) -> [SettingEntry] {
        switch section {
        case .general: SettingEntries.general
        case .github: SettingEntries.github
        case .keywords: keywords.map(KeywordSettings.entry(for:))
        case .extensions: ExtensionSettings.entries()
        case .data: SettingEntries.data
        }
    }
}

/// Hosts the Settings page in a tab's content area.
final class SettingsHostingView: NSHostingView<SettingsPage> {
    func focusSearch() { rootView.model.focusRequest += 1 }
}

struct SettingsPage: View {
    @Bindable var model: SettingsModel
    @FocusState private var searchFocused: Bool
    /// The column is placed from the page's width, not the width a visible scroller leaves, so nothing moves as results change.
    @State private var pageWidth: CGFloat = 0

    static func host() -> SettingsHostingView {
        let view = SettingsHostingView(rootView: SettingsPage(model: SettingsModel()))
        // The window sets the frame; the page scrolls rather than sizing the window.
        view.sizingOptions = []
        return view
    }

    private static let columnWidth: CGFloat = 680

    var body: some View {
        let filter = SettingsFilter(query: model.query)
        let matches = Dictionary(uniqueKeysWithValues: SettingsSection.allCases.map { section in
            (section, filter.isActive ? model.entries(for: section).filter(filter.shows).count : nil as Int?)
        })
        VStack(spacing: 0) {
            header(filter: filter, matches: matches)
            SettingsRule()
            ScrollView {
                column {
                    if filter.isActive, matches.values.allSatisfy({ $0 == 0 }) {
                        noMatches
                    } else {
                        VStack(alignment: .leading, spacing: 40) {
                            ForEach(SettingsSection.allCases) { section in
                                if matches[section] != 0 { sectionBlock(section).id(section) }
                            }
                        }
                        .scrollTargetLayout()
                        footer
                    }
                }
                .padding(.top, 24).padding(.bottom, 40)
            }
            .scrollPosition(id: $model.visibleSection, anchor: .top)
        }
        .environment(\.settingsFilter, filter)
        .background(Color(nsColor: Theme.chromeSurface))
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { pageWidth = $0 }
        .onAppear { searchFocused = true }
        .onChange(of: model.focusRequest) { searchFocused = true }
    }

    /// Up to 680pt with 20pt gutters, centered on the page. A visible scroller only eats into the right gutter.
    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let width = max(0, min(Self.columnWidth, pageWidth - 40))
        return VStack(alignment: .leading, spacing: 0, content: content)
            .frame(width: width, alignment: .leading)
            .padding(.leading, (pageWidth - width) / 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Header

    private func header(filter: SettingsFilter, matches: [SettingsSection: Int?]) -> some View {
        column {
            Text("Settings").font(.system(size: 20, weight: .semibold)).foregroundStyle(settingsPrimary)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 14)
            searchField
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    ForEach(SettingsSection.allCases) { section in indexButton(section, matches: matches[section] ?? nil, filter: filter) }
                }
            }
            .scrollIndicators(.never)
            .padding(.top, 10)
        }
        .padding(.top, 24).padding(.bottom, 8)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(settingsTertiary)
                .accessibilityHidden(true)
            TextField("Search settings", text: $model.query)
                .textFieldStyle(.plain).font(.system(size: 13))
                .tint(Color(nsColor: Theme.accent))
                .focused($searchFocused)
                .accessibilityLabel("Search settings")
                .onKeyPress(.escape) {
                    guard !model.query.isEmpty else { return .ignored }
                    model.query = ""
                    return .handled
                }
            if model.query.isEmpty {
                Text("⌘F").font(.system(size: 11).monospacedDigit()).foregroundStyle(settingsTertiary).accessibilityHidden(true)
            } else {
                Text("esc").font(.system(size: 11)).foregroundStyle(settingsTertiary).accessibilityHidden(true)
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(settingsTertiary)
                }
                .buttonStyle(.plain).help("Clear search (Esc)").accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius)
            .fill(Color(nsColor: searchFocused ? Theme.neutral(0) : Theme.fieldFill)))
        .overlay {
            if searchFocused {
                RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Color(nsColor: Theme.accent), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
    }

    /// Jumps to a section. While searching, it shows how many rows match there.
    private func indexButton(_ section: SettingsSection, matches: Int?, filter: SettingsFilter) -> some View {
        let isCurrent = !filter.isActive && model.visibleSection == section
        return Button { model.visibleSection = section } label: {
            HStack(spacing: 5) {
                Text(section.indexTitle)
                if let matches {
                    Text("\(matches)").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(settingsTertiary)
                }
            }
            .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
            .foregroundStyle(isCurrent ? settingsPrimary : settingsSecondary)
            .padding(.horizontal, 9).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 5).fill(isCurrent ? Color(nsColor: Theme.hoverFill) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(matches == 0)
        .opacity(matches == 0 ? 0.5 : 1)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .accessibilityValue(matches.map { "\($0) matching" } ?? "")
    }

    // MARK: Body

    private func sectionBlock(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(settingsPrimary)
                    .accessibilityAddTraits(.isHeader)
                Text(section.summary).font(.system(size: 12)).foregroundStyle(settingsTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 12)
            switch section {
            case .general: GeneralSettings()
            case .github: GitHubSettings()
            case .keywords: KeywordSettings(model: model)
            case .extensions: ExtensionSettings()
            case .data: BrowsingDataSettings()
            }
        }
    }

    private var noMatches: some View {
        VStack(spacing: 10) {
            Text("No settings match “\(model.query.trimmingCharacters(in: .whitespaces))”")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(settingsPrimary)
            Text("Search looks at every setting, keyword, and extension by name and description.")
                .font(.system(size: 12)).foregroundStyle(settingsSecondary).multilineTextAlignment(.center)
            Button("Clear Search") {
                model.query = ""
                searchFocused = true
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.top, 48)
    }

    private var footer: some View {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "—"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return Text("Koala \(version) (\(build))")
            .font(.system(size: 11, design: .monospaced)).foregroundStyle(settingsTertiary)
            .textSelection(.enabled)
            .padding(.top, 40)
    }
}

// MARK: Rows

/// A one-pixel separator from the neutral ramp.
struct SettingsRule: View {
    @Environment(\.pixelLength) private var pixel
    var body: some View { Rectangle().fill(Color(nsColor: Theme.hairline)).frame(height: pixel) }
}

/// The frame every row shares: hidden when the search doesn't match, a hairline above, a 44pt minimum.
struct SettingsRowFrame<Content: View>: View {
    let entry: SettingEntry
    @ViewBuilder var content: Content
    @Environment(\.settingsFilter) private var filter

    init(_ entry: SettingEntry, @ViewBuilder content: () -> Content) {
        self.entry = entry
        self.content = content()
    }

    var body: some View {
        if filter.shows(entry) {
            content
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .overlay(alignment: .top) { SettingsRule() }
        }
    }
}

/// A row title with the search's matches set in bold.
struct SettingTitle: View {
    let text: String
    var weight: Font.Weight = .regular
    @Environment(\.settingsFilter) private var filter

    init(_ text: String, weight: Font.Weight = .regular) {
        self.text = text
        self.weight = weight
    }

    var body: some View {
        Text(filter.highlight(text, size: 13)).font(.system(size: 13, weight: weight)).foregroundStyle(settingsPrimary)
    }
}

struct SettingDetail: View {
    let text: String?
    @Environment(\.settingsFilter) private var filter
    var body: some View {
        if let text {
            Text(filter.highlight(text, size: 11)).font(.system(size: 11)).foregroundStyle(settingsTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Title and detail on the leading side, the control trailing.
struct SettingRow<Detail: View, Control: View>: View {
    let entry: SettingEntry
    @ViewBuilder var detail: Detail
    @ViewBuilder var control: Control

    init(_ entry: SettingEntry, @ViewBuilder detail: () -> Detail, @ViewBuilder control: () -> Control) {
        self.entry = entry
        self.detail = detail()
        self.control = control()
    }

    var body: some View {
        SettingsRowFrame(entry) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    SettingTitle(entry.title)
                    detail
                }
                Spacer(minLength: 16)
                control.fixedSize()
            }
            .accessibilityElement(children: .contain)
        }
    }
}

extension SettingRow where Detail == SettingDetail {
    init(_ entry: SettingEntry, @ViewBuilder control: () -> Control) {
        self.init(entry, detail: { SettingDetail(text: entry.detail) }, control: control)
    }
}

/// The filled primary action: deep teal behind white in light appearance, teal behind dark text in dark.
struct SettingsPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color(nsColor: Theme.onAccent))
            .padding(.horizontal, 12).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Color(nsColor: Theme.accentText)))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.5)
            .contentShape(RoundedRectangle(cornerRadius: Theme.controlRadius))
    }
}

extension Toggle {
    /// A small switch without its label (the row names it). On reads in a neutral tint; teal stays on focus and primary actions.
    func settingsSwitch() -> some View {
        labelsHidden().toggleStyle(.switch).controlSize(.small).tint(Color(nsColor: Theme.switchTint))
    }
}
