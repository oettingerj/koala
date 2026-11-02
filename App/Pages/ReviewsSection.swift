import AppKit
import BrowserKit
import SwiftUI

/// The home page's Reviews: pull requests waiting on your review (directly or through a team) and
/// your own, in one flat list per tab that you narrow by typing and with facet chips.
/// Drafts and bot pull requests stay out of the list until the Show menu lets them in.
@MainActor
@Observable
final class ReviewsModel {
    enum Tab: String, CaseIterable, Identifiable {
        case requested, mine
        var id: String { rawValue }
        var title: String { self == .requested ? "Review Requested" : "My PRs" }
    }

    enum Sort: String, CaseIterable, Identifiable {
        case updated, oldest, smallest
        var id: String { rawValue }
        var title: String {
            switch self {
            case .updated: "Recently Updated"
            case .oldest: "Oldest First"
            case .smallest: "Smallest First"
            }
        }
    }

    var tab = Tab(rawValue: UserDefaults.standard.string(forKey: "ReviewsTab") ?? "") ?? .requested {
        didSet {
            UserDefaults.standard.set(tab.rawValue, forKey: "ReviewsTab")
            if tab != oldValue { clearFilters() }
        }
    }
    var sort = Sort(rawValue: UserDefaults.standard.string(forKey: "ReviewsSort") ?? "") ?? .updated {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: "ReviewsSort") }
    }
    var query = ""
    var repo: String?
    var author: String?
    var checks: GitHubStatus.Checks?
    var showTeamRequests = true
    var showDrafts = false
    var showBots = false
    /// The row a click or the arrow keys pick, which Return opens and the detail pane holds to.
    var selection: GitHubPull.ID?
    /// The row last pointed at, which the detail pane follows while nothing is selected.
    var previewID: GitHubPull.ID?
    var focusRequest = 0

    @ObservationIgnored let open: (URL, PageOpenTarget) -> Void
    private var github: GitHubService { .shared }

    init(open: @escaping (URL, PageOpenTarget) -> Void) { self.open = open }

    var filter: PageFilter { PageFilter(query: query) }

    /// Every pull request in the current tab, before filters.
    var all: [GitHubPull] { pulls(in: tab) }

    func pulls(in tab: Tab) -> [GitHubPull] { tab == .requested ? github.pulls.reviewRequested : github.pulls.mine }

    func total(in tab: Tab) -> Int { tab == .requested ? github.pulls.reviewRequestedTotal : github.pulls.mineTotal }

    var rows: [GitHubPull] {
        let filter = filter
        let rows = all.filter { pull in
            isShown(pull)
                && (repo == nil || pull.repo == repo)
                && (author == nil || pull.author == author)
                && (checks == nil || pull.checks == checks)
                && (!filter.isActive || filter.matches(Self.haystack(pull)))
        }
        return switch sort {
        case .updated: rows.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        case .oldest: rows.sorted { ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture) }
        case .smallest: rows.sorted { $0.additions + $0.deletions < $1.additions + $1.deletions }
        }
    }

    static func haystack(_ pull: GitHubPull) -> String {
        ([pull.title, pull.repo, pull.author ?? "", "\(pull.number)", pull.headRef ?? "", pull.requestedTeam ?? ""]
            + pull.labels + pull.areas.map(\.name)).joined(separator: " ")
    }

    var repos: [String] { Array(Set(all.map(\.repo))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    var authors: [String] { Array(Set(all.compactMap(\.author))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    var hasTeamRequests: Bool { all.contains(where: \.isTeamRequest) }

    /// Whether the Show menu lets this kind of pull request into the list.
    func isShown(_ pull: GitHubPull) -> Bool {
        (showTeamRequests || !pull.isTeamRequest) && (showDrafts || !pull.isDraft) && (showBots || !pull.isBot)
    }

    /// Pull requests in the current tab that the Show menu leaves out.
    var hiddenCount: Int { all.count { !isShown($0) } }

    /// The Show menu differs from its defaults.
    var isShowChanged: Bool { !showTeamRequests || showDrafts || showBots }

    var isFiltered: Bool { filter.isActive || repo != nil || author != nil || checks != nil || isShowChanged }

    func clearFilters() {
        query = ""
        repo = nil
        author = nil
        checks = nil
        showTeamRequests = true
        showDrafts = false
        showBots = false
        selection = nil
        previewID = nil
    }

    /// Lets every kind of pull request into the list.
    func showAll() {
        showTeamRequests = true
        showDrafts = true
        showBots = true
    }

    // MARK: Keyboard

    func moveSelection(by offset: Int) {
        let rows = rows
        guard !rows.isEmpty else { return }
        let current = selection.flatMap { id in rows.firstIndex { $0.id == id } }
        let next = current.map { min(max($0 + offset, 0), rows.count - 1) } ?? (offset > 0 ? 0 : rows.count - 1)
        selection = rows[next].id
    }

    /// What the detail pane shows: the selection while it's in the list, else the row pointed at, else the first row.
    func previewed(in rows: [GitHubPull]) -> GitHubPull? {
        rows.first { $0.id == selection } ?? rows.first { $0.id == previewID } ?? rows.first
    }

    /// Opens the selected row, or the first when none is selected.
    func openSelection(_ target: PageOpenTarget) {
        let rows = rows
        guard let pull = rows.first(where: { $0.id == selection }) ?? rows.first else { return }
        open(pull.url, target)
    }
}

// MARK: View

struct ReviewsSection: View {
    @Bindable var model: ReviewsModel
    /// The home page's sidebar, when the page is wide enough to show one.
    var sidebarShown: Binding<Bool>?
    @FocusState private var searchFocused: Bool
    @State private var width: CGFloat = 0
    private var github: GitHubService { .shared }

    private static let columnWidth: CGFloat = 960
    /// With the detail pane the column grows to fit it beside the list.
    private static let paneColumnWidth: CGFloat = 1280
    /// The list keeps about 800pt beside the pane, so titles and gists stay readable.
    private static let paneMinimumWidth: CGFloat = 1180
    static let paneWidth: CGFloat = 320
    /// Between the list and the pane's hairline.
    private static let listGap: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            column { header }
                .padding(.top, 24).padding(.bottom, 10)
            SettingsRule()
            content
        }
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { width = $0 }
        .onChange(of: model.focusRequest) { searchFocused = true }
    }

    /// Wide pages show the detail pane beside the list.
    private var showsPane: Bool { width >= Self.paneMinimumWidth }

    private var columnWidth: CGFloat { max(0, min(showsPane ? Self.paneColumnWidth : Self.columnWidth, width - 40)) }

    /// Up to 960pt (1280pt with the pane) with 20pt gutters, centered.
    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .frame(width: columnWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
    }

    private var listWidth: CGFloat { showsPane ? columnWidth - Self.paneWidth - 1 - Self.listGap : columnWidth }

    /// Narrow lists drop the login, team, diffstat, decision words, and second-line facts from rows.
    private var isCompact: Bool { listWidth < 680 }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                if let sidebarShown { SidebarToggle(isShown: sidebarShown) }
                Text("Reviews").font(.system(size: 20, weight: .semibold)).foregroundStyle(settingsPrimary)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 16)
                if github.isSignedIn { refreshControl }
            }
            .frame(height: 28)
            .padding(.bottom, 12)
            if github.isSignedIn {
                // Until the first list arrives, and over an empty tab, nothing offers to filter nothing;
                // the controls keep their space so the rows land where the placeholders sit.
                // A failed first load has no rows to land, so it gives the space back.
                let isLoaded = github.pullsUpdatedAt != nil
                let canFilter = isLoaded && (!model.all.isEmpty || model.isFiltered)
                if isLoaded || github.lastError == nil {
                    tabs.padding(.bottom, 12).opacity(isLoaded ? 1 : 0).disabled(!isLoaded)
                        .accessibilityHidden(!isLoaded)
                    PageSearchField(prompt: "Search title, repository, author, number, or branch", text: $model.query,
                                    focused: $searchFocused, onKey: handleKey)
                        .opacity(canFilter ? 1 : 0).disabled(!canFilter).accessibilityHidden(!canFilter)
                    facets.padding(.top, 10).opacity(canFilter ? 1 : 0).disabled(!canFilter).accessibilityHidden(!canFilter)
                }
            }
        }
    }

    private var refreshControl: some View {
        HStack(spacing: 6) {
            if let updated = github.pullsUpdatedAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Updated \(RelativeAge.long(since: updated, now: context.date))")
                        .font(.system(size: 11).monospacedDigit()).foregroundStyle(settingsTertiary)
                }
            }
            Button { github.refreshPulls() } label: {
                ZStack {
                    if github.isRefreshingPulls {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13, weight: .medium)).foregroundStyle(settingsSecondary)
                    }
                }
                .frame(width: Theme.iconButtonSize, height: Theme.iconButtonSize)
                .contentShape(Rectangle())
            }
            .buttonStyle(HoverFillButtonStyle(radius: Theme.controlRadius))
            .disabled(github.isRefreshingPulls)
            .help("Refresh (⌘R)")
            .accessibilityLabel("Refresh")
        }
    }

    private var tabs: some View {
        HStack(spacing: 2) {
            ForEach(ReviewsModel.Tab.allCases) { tab in
                let isCurrent = model.tab == tab
                Button { model.tab = tab } label: {
                    HStack(spacing: 5) {
                        Text(tab.title)
                        if github.pullsUpdatedAt != nil {
                            Text("\(model.pulls(in: tab).count(where: model.isShown))")
                                .font(.mono(size: 10, weight: .medium)).foregroundStyle(settingsTertiary)
                        }
                    }
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? settingsPrimary : settingsSecondary)
                    .padding(.horizontal, 9).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 5).fill(isCurrent ? Color(nsColor: Theme.hoverFill) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(tab == .requested ? "1" : "2", modifiers: [.command, .option])
                .help("\(tab.title) (⌥⌘\(tab == .requested ? 1 : 2))")
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
    }

    private var facets: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    FacetMenu(title: "Repository", value: model.repo, options: model.repos, selection: $model.repo, mono: true)
                    if model.tab == .requested {
                        FacetMenu(title: "Author", value: model.author, options: model.authors, selection: $model.author, mono: true)
                    }
                    FacetMenu(title: "Checks", value: model.checks.map(Self.checksTitle),
                              options: [GitHubStatus.Checks.failing, .pending, .passing, .none], selection: $model.checks,
                              label: Self.checksTitle)
                    showMenu
                    if model.isFiltered {
                        Button { model.clearFilters() } label: {
                            Text("Clear").font(.system(size: 12)).foregroundStyle(settingsSecondary)
                                .padding(.horizontal, 8).frame(height: 24).contentShape(Rectangle())
                        }
                        .buttonStyle(HoverFillButtonStyle())
                        .help("Clear the search and every filter")
                    }
                }
            }
            .scrollIndicators(.never)
            Spacer(minLength: 8)
            Menu {
                Picker("Sort", selection: $model.sort) {
                    ForEach(ReviewsModel.Sort.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline).labelsHidden()
            } label: {
                HStack(spacing: 4) {
                    Text(model.sort.title)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                }
                .font(.system(size: 12)).foregroundStyle(settingsSecondary)
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .accessibilityLabel("Sort: \(model.sort.title)")
        }
        .frame(height: 24)
    }

    /// One menu for the kinds of pull request the list includes, each with how many the tab has.
    /// At rest it counts what it leaves out; changed, it fills like a set facet.
    private var showMenu: some View {
        let all = model.all, hidden = model.hiddenCount
        return Menu {
            if model.tab == .requested, model.hasTeamRequests {
                Toggle(isOn: $model.showTeamRequests) { Text("Team Requests") }
                    .badge(all.count(where: \.isTeamRequest))
            }
            Toggle(isOn: $model.showDrafts) { Text("Drafts") }
                .badge(all.count(where: \.isDraft))
            Toggle(isOn: $model.showBots) { Text("Bots") }
                .badge(all.count(where: \.isBot))
            if hidden > 0 {
                Divider()
                Button("Show All") { model.showAll() }
            }
        } label: {
            HStack(spacing: 4) {
                Text("Show").font(.system(size: 12, weight: model.isShowChanged ? .medium : .regular))
                    .foregroundStyle(model.isShowChanged ? settingsPrimary : settingsSecondary)
                if hidden > 0 {
                    Text("\(hidden) hidden").font(.mono(size: 10, weight: .medium))
                        .foregroundStyle(settingsTertiary)
                }
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(settingsTertiary)
            }
            .padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: model.isShowChanged ? Theme.hoverFill : Theme.fieldFill)))
            .contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .help("Choose whether team requests, drafts, and bot pull requests appear")
        .accessibilityLabel(hidden > 0 ? "Show, \(hidden) hidden" : "Show")
    }

    static func checksTitle(_ checks: GitHubStatus.Checks) -> String {
        switch checks {
        case .failing: "Failing"
        case .pending: "Running"
        case .passing: "Passing"
        case .none: "No checks"
        }
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        switch press.key {
        case .downArrow: model.moveSelection(by: 1)
        case .upArrow: model.moveSelection(by: -1)
        case .return: model.openSelection(.forClick(command: press.modifiers.contains(.command)))
        case .escape:
            guard model.selection != nil else { return .ignored }
            model.selection = nil
        default: return .ignored
        }
        return .handled
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if !github.isSignedIn {
            column { signedOut }.padding(.top, 32)
            Spacer()
        } else if github.pullsUpdatedAt == nil {
            if let error = github.lastError {
                column { errorLine(error).padding(.top, 16) }
                Spacer()
            } else {
                split { VStack(spacing: 0) { skeleton; Spacer(minLength: 0) } } pane: { Color.clear }
            }
        } else {
            let rows = model.rows
            if showsPane, !rows.isEmpty {
                split { list(rows) } pane: {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        if let pull = model.previewed(in: rows) {
                            PullDetailPane(pull: pull, tab: model.tab, now: context.date)
                        }
                    }
                }
                .onChange(of: model.previewed(in: rows)?.id, initial: true) { _, id in
                    if let id { PullSummarizer.shared.prioritize(id) }
                }
            } else {
                list(rows)
            }
        }
    }

    /// The list and, on wide pages, the detail pane behind a hairline, filling the height below the header.
    @ViewBuilder private func split<List: View, Pane: View>(@ViewBuilder _ list: () -> List, @ViewBuilder pane: () -> Pane) -> some View {
        if showsPane {
            HStack(alignment: .top, spacing: 0) {
                list().frame(maxWidth: .infinity, maxHeight: .infinity).padding(.trailing, Self.listGap)
                VerticalRule()
                pane().frame(width: Self.paneWidth).frame(maxHeight: .infinity, alignment: .top)
            }
            .frame(width: columnWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            column { list() }
            Spacer(minLength: 0)
        }
    }

    private var signedOut: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in to GitHub to see the pull requests waiting on your review, and your own, here on every new tab.")
                .font(.system(size: 13)).foregroundStyle(settingsSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Sign In…") { NSApp.sendAction(#selector(BrowserWindowController.signInToGitHub(_:)), to: nil, from: nil) }
                .buttonStyle(SettingsPrimaryButtonStyle())
        }
    }

    /// Placeholder rows while the first fetch runs; static, so nothing moves. They mirror both
    /// lines of a row, column for column.
    private var skeleton: some View {
        let fill = Color(nsColor: Theme.fieldFill)
        func bar(_ width: CGFloat, _ height: CGFloat = 10) -> some View {
            RoundedRectangle(cornerRadius: 3).fill(fill).frame(width: width, height: height)
        }
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(fill).frame(width: 12, height: 12).frame(width: 16, height: PullRow.firstLine)
                    VStack(alignment: .leading, spacing: PullRow.lineGap) {
                        HStack(spacing: 12) {
                            bar([280, 220, 340, 190, 260, 300][index])
                            Spacer(minLength: 12)
                            HStack(spacing: 6) {
                                Circle().fill(fill).frame(width: 16, height: 16)
                                if !isCompact { bar(56) }
                            }
                            .frame(width: isCompact ? 16 : PullRow.peopleWidth, alignment: .leading)
                            if !isCompact { bar(52).frame(width: PullRow.sizeWidth, alignment: .trailing) }
                            Circle().fill(fill).frame(width: 7, height: 7)
                            bar(20).frame(width: PullRow.ageWidth, alignment: .trailing)
                        }
                        .frame(height: PullRow.firstLine)
                        HStack(spacing: 12) {
                            bar([360, 300, 420, 260, 340, 380][index], 8)
                            Spacer(minLength: 0)
                        }
                        .frame(height: PullRow.secondLine)
                    }
                }
                .padding(.horizontal, 8).padding(.vertical, PullRow.verticalInset)
            }
        }
        .padding(.top, 8)
        .accessibilityElement()
        .accessibilityLabel("Loading pull requests")
    }

    private func errorLine(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(settingsFail)
                .accessibilityHidden(true)
            Text("Couldn’t load pull requests: \(message)").font(.system(size: 12)).foregroundStyle(settingsSecondary)
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Try Again") { github.refreshPulls() }.controlSize(.small)
        }
    }

    private func list(_ rows: [GitHubPull]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error = github.lastError { errorLine(error).padding(.bottom, 8) }
                    if rows.isEmpty {
                        emptyState.padding(.top, 16)
                    } else {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            LazyVStack(spacing: 0) {
                                ForEach(rows) { pull in
                                    PullRow(pull: pull, tab: model.tab, filter: model.filter, isSelected: model.selection == pull.id,
                                            isCompact: isCompact, now: context.date, open: model.open,
                                            onSelect: { model.selection = pull.id },
                                            onHover: { if $0 { model.previewID = pull.id } })
                                        .id(pull.id)
                                }
                            }
                        }
                        footer
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8).padding(.bottom, 40)
                // Centered like the header when the page has no pane; the split sizes it otherwise.
                .frame(width: showsPane ? nil : columnWidth)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: model.selection) { _, id in
                if let id { proxy.scrollTo(id) }
            }
        }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.isFiltered {
                Text("No pull requests match.").font(.system(size: 13)).foregroundStyle(settingsSecondary)
                Button("Clear Filters") { model.clearFilters() }.controlSize(.small)
            } else if model.hiddenCount > 0 {
                Text(model.hiddenCount == 1 ? "1 pull request is hidden." : "\(model.hiddenCount) pull requests are hidden.")
                    .font(.system(size: 13)).foregroundStyle(settingsSecondary)
                Button("Show All") { model.showAll() }.controlSize(.small)
            } else {
                Text(model.tab == .requested ? "Nothing waiting on your review." : "You have no open pull requests.")
                    .font(.system(size: 13)).foregroundStyle(settingsSecondary)
                Text(model.tab == .requested ? "Requests to you and your teams appear here." : "Pull requests you open appear here.")
                    .font(.system(size: 12)).foregroundStyle(settingsTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
    }

    @ViewBuilder private var footer: some View {
        let total = model.total(in: model.tab)
        if total > model.all.count {
            HStack(spacing: 6) {
                Text("Showing the \(model.all.count) most recently updated of \(total).")
                    .font(.system(size: 11).monospacedDigit()).foregroundStyle(settingsTertiary)
                Button("Open on GitHub") {
                    let path = model.tab == .requested ? "pulls/review-requested" : "pulls"
                    model.open(URL(string: "https://github.com/\(path)")!, .forCurrentEvent)
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(settingsSecondary)
            }
            .padding(.top, 16).padding(.horizontal, 8)
        }
    }
}

// MARK: Row

struct PullRow: View {
    let pull: GitHubPull
    let tab: ReviewsModel.Tab
    let filter: PageFilter
    let isSelected: Bool
    let isCompact: Bool
    let now: Date
    let open: (URL, PageOpenTarget) -> Void
    /// A single click: the row becomes the selection and the detail pane holds to it.
    var onSelect: () -> Void = {}
    /// Pointer movement over the row or VoiceOver focus on it: the detail pane follows either while nothing is selected.
    var onHover: (Bool) -> Void = { _ in }
    @State private var isHovered = false
    @AccessibilityFocusState private var isFocused: Bool
    /// Where the pointer was when a row last took the preview. Rows scrolling under a still pointer
    /// (arrow keys, a refresh) don't take it from the keyboard selection.
    private static var lastPointer = NSPoint(x: -1, y: -1)
    private var summarizer: PullSummarizer { .shared }

    // Two lines on a 4pt grid: 8 + 18 + 2 + 16 + 8 = 52pt.
    static let firstLine: CGFloat = 18
    static let secondLine: CGFloat = 16
    static let lineGap: CGFloat = 2
    static let verticalInset: CGFloat = 8
    // Trailing columns, shared by both lines so the facts stack under the ones they belong with.
    static let peopleWidth: CGFloat = 120
    static let sizeWidth: CGFloat = 84
    static let ageWidth: CGFloat = 30
    /// The checks dot, the gap, and the age, which the comment count spans on the second line.
    static let activityWidth: CGFloat = 7 + 12 + ageWidth

    /// Tertiary text steps up to secondary on the selected row, so it clears 4.5:1 on the pressed fill.
    private var quiet: Color { isSelected ? settingsSecondary : settingsTertiary }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            stateGlyph
            VStack(alignment: .leading, spacing: Self.lineGap) {
                HStack(spacing: 12) {
                    headline
                    Spacer(minLength: 12)
                    trailing
                }
                .frame(height: Self.firstLine)
                HStack(spacing: 12) {
                    gist
                    if !isCompact {
                        Spacer(minLength: 12)
                        facts
                    }
                }
                .frame(height: Self.secondLine)
            }
        }
        .padding(.horizontal, 8).padding(.vertical, Self.verticalInset)
        // Keyboard selection sits one ramp step deeper than hover, so Return's target is never ambiguous.
        .background(RoundedRectangle(cornerRadius: 5).fill(
            isSelected ? Color(nsColor: Theme.pressedFill) : isHovered ? Color(nsColor: Theme.hoverFill) : .clear))
        .contentShape(Rectangle())
        .onHover { inside in
            isHovered = inside
            let pointer = NSEvent.mouseLocation
            if inside, pointer != Self.lastPointer {
                Self.lastPointer = pointer
                onHover(true)
            }
        }
        // One tap gesture sees both clicks of a double-click, so the first selects at once and the second opens.
        .onTapGesture {
            if NSApp.currentEvent?.clickCount == 2 { open(pull.url, .forCurrentEvent) } else { onSelect() }
        }
        .help(helpText)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isLink, .isSelected] : .isLink)
        .accessibilityAction { open(pull.url, .newTab) }
        .accessibilityFocused($isFocused)
        .onChange(of: isFocused) { _, focused in if focused { onHover(true) } }
    }

    private var stateGlyph: some View {
        Group {
            if let image = GitHubStyle.image(pull.isDraft ? .draft : .open, size: 12) {
                Image(nsImage: image)
            }
        }
        .frame(width: 16, height: Self.firstLine)
    }

    private var headline: some View {
        HStack(spacing: 8) {
            Text(filter.highlight(pull.title, size: 13))
                .font(.system(size: 13, weight: isSelected ? .medium : .regular)).foregroundStyle(settingsPrimary)
                .lineLimit(1)
            // The reference is what an engineer copies, so the title truncates first.
            HStack(spacing: 0) {
                Text(filter.highlight(pull.repo, size: 11, mono: true)).foregroundStyle(settingsSecondary)
                Text(verbatim: "#\(pull.number)").foregroundStyle(quiet)
            }
            .font(.mono(size: 11)).lineLimit(1).fixedSize()
            if !isCompact, pull.isTeamRequest, let team = pull.requestedTeam {
                HStack(spacing: 3) {
                    Image(systemName: "person.2").font(.system(size: 9, weight: .medium)).accessibilityHidden(true)
                    Text(filter.highlight(team, size: 11, mono: true)).font(.mono(size: 11)).lineLimit(1)
                }
                .foregroundStyle(quiet)
                .help("Requested of the \(team) team")
            }
        }
    }

    private var trailing: some View {
        HStack(spacing: 12) {
            if tab == .requested {
                HStack(spacing: 6) {
                    AvatarView(url: pull.authorAvatarURL)
                    if !isCompact, let author = pull.author {
                        Text(filter.highlight(author, size: 11, mono: true)).font(.mono(size: 11))
                            .foregroundStyle(settingsSecondary).lineLimit(1)
                    }
                }
                .frame(width: isCompact ? 16 : Self.peopleWidth, alignment: .leading)
            } else {
                reviewDecision.frame(width: isCompact ? 16 : Self.peopleWidth, alignment: .leading)
            }
            if !isCompact {
                HStack(spacing: 4) {
                    Text(verbatim: "+\(pull.additions)")
                    Text(verbatim: "−\(pull.deletions)")
                }
                .font(.mono(size: 11)).foregroundStyle(quiet)
                .frame(width: Self.sizeWidth, alignment: .trailing)
            }
            Circle().fill(Color(nsColor: GitHubStyle.color(pull.checks) ?? .clear)).frame(width: 7, height: 7)
                .help(GitHubStyle.label(pull.checks).map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "No checks")
            Text(pull.updatedAt.map { RelativeAge.short(since: $0, now: now) } ?? "")
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(quiet)
                .frame(width: Self.ageWidth, alignment: .trailing)
        }
    }

    // MARK: Second line

    /// What the pull request is about: the written gist, else the author's first paragraph.
    private var about: String? { summarizer.summary(for: pull.id)?.gist ?? pull.excerpt }

    /// The second line's text was written by the model rather than the author.
    private var isGenerated: Bool { summarizer.summary(for: pull.id) != nil }

    private var areasText: String? {
        guard !pull.areas.isEmpty else { return nil }
        let names = pull.areas.prefix(2).map(\.name).joined(separator: " · ")
        return pull.areas.count > 2 ? "\(names) +\(pull.areas.count - 2)" : names
    }

    private var branchText: String? {
        guard let head = pull.headRef, let base = pull.baseRef else { return nil }
        return "\(head) → \(base)"
    }

    /// The gist, given the whole line. Without a gist the areas it touches lead, then the branch;
    /// while the gist is being written over an empty description, a still placeholder holds its place.
    @ViewBuilder private var gist: some View {
        if let about {
            HStack(spacing: 5) {
                if isGenerated {
                    Image(systemName: "apple.intelligence").font(.system(size: 9)).foregroundStyle(quiet)
                        .accessibilityHidden(true)
                }
                Text(about).font(.system(size: 12)).foregroundStyle(settingsSecondary).lineLimit(1)
            }
            .help(isGenerated ? "Summarized on this Mac by Apple Intelligence" : "")
            .layoutPriority(1)
        } else if summarizer.isPending(pull.id) {
            RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: Theme.fieldFill)).frame(width: 160, height: 8)
                .accessibilityHidden(true)
        } else if let lead = areasText ?? branchText {
            Text(lead).font(.mono(size: 11)).foregroundStyle(quiet).lineLimit(1)
        }
    }

    /// Reviews, size, and conversation, each under the first-line column it belongs with.
    private var facts: some View {
        HStack(spacing: 12) {
            // Review Requested counts reviews so far; My PRs already shows the decision above, so it names who's left.
            Group { if tab == .requested { reviewCounts } else { waiting } }
                .frame(width: Self.peopleWidth, alignment: .leading)
            Text(pull.changedFiles == 1 ? "1 file" : "\(pull.changedFiles) files")
                .font(.mono(size: 11)).foregroundStyle(quiet).lineLimit(1)
                .frame(width: Self.sizeWidth, alignment: .trailing)
                .opacity(pull.changedFiles > 0 ? 1 : 0)
            HStack(spacing: 3) {
                if pull.commentCount > 0 {
                    Image(systemName: "bubble.left").font(.system(size: 9, weight: .medium)).accessibilityHidden(true)
                    Text("\(pull.commentCount)").font(.system(size: 11).monospacedDigit())
                }
            }
            .foregroundStyle(quiet)
            .frame(width: Self.activityWidth, alignment: .trailing)
            .help(pull.commentCount == 1 ? "1 comment" : "\(pull.commentCount) comments")
        }
    }

    /// Approvals and requests for changes so far: convention-colored glyphs beside tabular counts.
    private var reviewCounts: some View {
        HStack(spacing: 8) {
            // The first glyph takes the avatar's 16pt and gap, so its count starts under the login.
            if pull.approvals > 0 { count("checkmark", Theme.pass, pull.approvals, leading: true) }
            if pull.changeRequests > 0 { count("exclamationmark", Theme.fail, pull.changeRequests, leading: pull.approvals == 0) }
        }
        .help(reviewHelp)
    }

    @ViewBuilder private var waiting: some View {
        if !pull.pendingReviewers.isEmpty {
            // Glyph framed like the decision glyph above, so the names start under its words.
            HStack(spacing: 5) {
                Image(systemName: "hourglass").font(.system(size: 9, weight: .medium)).frame(width: 12).accessibilityHidden(true)
                Text(pull.pendingReviewers.joined(separator: ", ")).font(.mono(size: 11)).lineLimit(1)
            }
            .foregroundStyle(quiet)
            .help("Waiting on \(pull.pendingReviewers.joined(separator: ", "))")
        }
    }

    /// On the selected row the glyph steps to secondary: state hues fall under 3:1 on the pressed fill,
    /// and the shape still tells approval from changes.
    private func count(_ symbol: String, _ color: NSColor, _ value: Int, leading: Bool) -> some View {
        HStack(spacing: leading ? 6 : 3) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold))
                .foregroundStyle(isSelected ? settingsSecondary : Color(nsColor: color))
                .frame(width: leading ? 16 : nil)
            Text("\(value)").font(.mono(size: 11)).foregroundStyle(quiet)
        }
    }

    private var reviewHelp: String {
        let approved = pull.reviews.filter { $0.state == .approved }.map(\.login)
        let changes = pull.reviews.filter { $0.state == .changesRequested }.map(\.login)
        var parts: [String] = []
        if !approved.isEmpty { parts.append("Approved by \(approved.joined(separator: ", "))") }
        if !changes.isEmpty { parts.append("Changes requested by \(changes.joined(separator: ", "))") }
        return parts.joined(separator: "\n")
    }

    /// Approval state of your own pull request: a glyph in its convention color, words in text color.
    @ViewBuilder private var reviewDecision: some View {
        let decision: (symbol: String, color: NSColor, text: String)? = switch pull.reviewDecision {
        case "APPROVED": ("checkmark", Theme.pass, "Approved")
        case "CHANGES_REQUESTED": ("exclamationmark", Theme.fail, "Changes requested")
        case "REVIEW_REQUIRED": ("circle.dotted", Theme.textTertiary, "Review required")
        default: nil
        }
        if let decision {
            HStack(spacing: 5) {
                Image(systemName: decision.symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color(nsColor: decision.color))
                    .frame(width: 12)
                if !isCompact { Text(decision.text).font(.system(size: 11)).foregroundStyle(settingsSecondary).lineLimit(1) }
            }
            .help(decision.text)
        }
    }

    @ViewBuilder private var menu: some View {
        Button("Open in New Tab") { open(pull.url, .newTab) }
        Button("Open in Background Tab") { open(pull.url, .backgroundTab) }
        Button("Open in This Tab") { open(pull.url, .here) }
        Button("Copy Link") { Pasteboard.copy(url: pull.url, title: pull.title) }
        Divider()
        if let head = pull.headRef {
            Button("Copy Branch") { copy(head) }
        }
        Button("Copy Checkout Command") { copy("gh pr checkout \(pull.number) --repo \(pull.repo)") }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var helpText: String {
        var lines = [pull.title]
        if let head = pull.headRef, let base = pull.baseRef { lines.append("\(head) → \(base)") }
        return lines.joined(separator: "\n")
    }

    private var accessibilityText: String {
        var parts = [pull.isDraft ? "Draft pull request" : "Pull request", pull.title, "\(pull.repo) number \(pull.number)"]
        if let author = pull.author, tab == .requested { parts.append("by \(author)") }
        if pull.isTeamRequest { parts.append("requested of \(pull.requestedTeam ?? "your team")") }
        if let checks = GitHubStyle.label(pull.checks) { parts.append(checks) }
        if let about { parts.append(isGenerated ? "summary by Apple Intelligence: \(about)" : about) }
        if !pull.areas.isEmpty { parts.append("in \(pull.areas.prefix(3).map(\.name).joined(separator: ", "))") }
        parts.append("\(pull.additions) additions, \(pull.deletions) deletions")
        if pull.changedFiles > 0 { parts.append(pull.changedFiles == 1 ? "1 file" : "\(pull.changedFiles) files") }
        if pull.approvals > 0 { parts.append(pull.approvals == 1 ? "1 approval" : "\(pull.approvals) approvals") }
        if pull.changeRequests > 0 { parts.append(pull.changeRequests == 1 ? "1 request for changes" : "\(pull.changeRequests) requests for changes") }
        if pull.commentCount > 0 { parts.append(pull.commentCount == 1 ? "1 comment" : "\(pull.commentCount) comments") }
        if tab == .mine, !pull.pendingReviewers.isEmpty { parts.append("waiting on \(pull.pendingReviewers.joined(separator: ", "))") }
        if let updated = pull.updatedAt { parts.append("updated \(RelativeAge.long(since: updated, now: now))") }
        return parts.joined(separator: ", ")
    }
}

// MARK: Chips

/// A facet that picks one value from a menu. At rest it names the facet; set, it shows the value and a clear button.
private struct FacetMenu<Value: Hashable>: View {
    let title: String
    let value: String?
    let options: [Value]
    @Binding var selection: Value?
    var mono = false
    var label: (Value) -> String = { "\($0)" }

    var body: some View {
        HStack(spacing: 0) {
            Menu {
                Picker(title, selection: $selection) {
                    Text("Any").tag(Value?.none)
                    Divider()
                    ForEach(options, id: \.self) { Text(label($0)).tag(Optional($0)) }
                }
                .pickerStyle(.inline).labelsHidden()
            } label: {
                HStack(spacing: 4) {
                    if let value {
                        Text(value).font(mono ? .mono(size: 12, weight: .medium) : .system(size: 12, weight: .medium))
                            .foregroundStyle(settingsPrimary).lineLimit(1)
                    } else {
                        Text(title).font(.system(size: 12)).foregroundStyle(settingsSecondary)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(settingsTertiary)
                    }
                }
                .padding(.leading, 8).padding(.trailing, value == nil ? 8 : 4).frame(height: 24)
                .contentShape(Rectangle())
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .disabled(options.isEmpty)
            .accessibilityLabel(value.map { "\(title): \($0)" } ?? title)
            if value != nil {
                Button { selection = nil } label: {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(settingsTertiary)
                        .frame(width: 18, height: 24).contentShape(Rectangle())
                }
                .buttonStyle(.plain).help("Clear \(title.lowercased())").accessibilityLabel("Clear \(title.lowercased())")
            }
        }
        .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: value == nil ? Theme.fieldFill : Theme.hoverFill)))
        .opacity(options.isEmpty ? 0.5 : 1)
    }
}

/// A borderless button with hover and pressed fills, like the toolbar's icon buttons.
struct HoverFillButtonStyle: ButtonStyle {
    var radius: CGFloat = 5
    @State private var isHovered = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(RoundedRectangle(cornerRadius: radius).fill(
                configuration.isPressed ? Color(nsColor: Theme.pressedFill)
                    : isHovered && isEnabled ? Color(nsColor: Theme.hoverFill) : .clear))
            .onHover { isHovered = $0 }
    }
}

// MARK: Ages

enum RelativeAge {
    /// "now", "5m", "3h", "2d", "6w", "4mo", "2y": compact enough for a row's trailing column.
    static func short(since date: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let minutes = Int(seconds / 60), hours = minutes / 60, days = hours / 24
        if minutes < 1 { return "now" }
        if hours < 1 { return "\(minutes)m" }
        if days < 1 { return "\(hours)h" }
        if days < 14 { return "\(days)d" }
        if days < 60 { return "\(days / 7)w" }
        if days < 365 { return "\(days / 30)mo" }
        return "\(days / 365)y"
    }

    /// "just now", "2 minutes ago", for headers and VoiceOver.
    static func long(since date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "just now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .wide))
    }
}
