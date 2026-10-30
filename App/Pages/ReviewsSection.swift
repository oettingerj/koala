import AppKit
import BrowserKit
import SwiftUI

/// The home page's Reviews: pull requests waiting on your review (directly or through a team) and
/// your own, in one flat list per tab that you narrow by typing and with facet chips.
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
    var directOnly = false
    var repo: String?
    var author: String?
    var checks: GitHubStatus.Checks?
    var hideDrafts = false
    /// The row arrow keys move and Return opens.
    var selection: GitHubPull.ID?
    var focusRequest = 0

    @ObservationIgnored let open: (URL, _ newTab: Bool) -> Void
    private var github: GitHubService { .shared }

    init(open: @escaping (URL, Bool) -> Void) { self.open = open }

    var filter: PageFilter { PageFilter(query: query) }

    /// Every pull request in the current tab, before filters.
    var all: [GitHubPull] { pulls(in: tab) }

    func pulls(in tab: Tab) -> [GitHubPull] { tab == .requested ? github.pulls.reviewRequested : github.pulls.mine }

    func total(in tab: Tab) -> Int { tab == .requested ? github.pulls.reviewRequestedTotal : github.pulls.mineTotal }

    var rows: [GitHubPull] {
        let filter = filter
        let rows = all.filter { pull in
            (!directOnly || !pull.isTeamRequest)
                && (repo == nil || pull.repo == repo)
                && (author == nil || pull.author == author)
                && (checks == nil || pull.checks == checks)
                && (!hideDrafts || !pull.isDraft)
                && (!filter.isActive || filter.matches(Self.haystack(pull)))
        }
        return switch sort {
        case .updated: rows.sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
        case .oldest: rows.sorted { ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture) }
        case .smallest: rows.sorted { $0.additions + $0.deletions < $1.additions + $1.deletions }
        }
    }

    static func haystack(_ pull: GitHubPull) -> String {
        [pull.title, pull.repo, pull.author ?? "", "\(pull.number)", pull.headRef ?? "", pull.requestedTeam ?? ""].joined(separator: " ")
    }

    var repos: [String] { Array(Set(all.map(\.repo))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    var authors: [String] { Array(Set(all.compactMap(\.author))).sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
    var hasTeamRequests: Bool { all.contains(where: \.isTeamRequest) }

    var isFiltered: Bool { filter.isActive || directOnly || repo != nil || author != nil || checks != nil || hideDrafts }

    func clearFilters() {
        query = ""
        directOnly = false
        repo = nil
        author = nil
        checks = nil
        hideDrafts = false
        selection = nil
    }

    // MARK: Keyboard

    func moveSelection(by offset: Int) {
        let rows = rows
        guard !rows.isEmpty else { return }
        let current = selection.flatMap { id in rows.firstIndex { $0.id == id } }
        let next = current.map { min(max($0 + offset, 0), rows.count - 1) } ?? (offset > 0 ? 0 : rows.count - 1)
        selection = rows[next].id
    }

    /// Opens the selected row, or the first when none is selected.
    func openSelection(newTab: Bool) {
        let rows = rows
        guard let pull = rows.first(where: { $0.id == selection }) ?? rows.first else { return }
        open(pull.url, newTab)
    }
}

// MARK: View

struct ReviewsSection: View {
    @Bindable var model: ReviewsModel
    @FocusState private var searchFocused: Bool
    @State private var width: CGFloat = 0
    private var github: GitHubService { .shared }

    private static let columnWidth: CGFloat = 960

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

    /// Up to 960pt with 20pt gutters, centered.
    private func column<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let column = max(0, min(Self.columnWidth, width - 40))
        return VStack(alignment: .leading, spacing: 0, content: content)
            .frame(width: column, alignment: .leading)
            .frame(maxWidth: .infinity)
    }

    /// Narrow pages drop the author's login and the diffstat from rows.
    private var isCompact: Bool { width < 720 }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
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
                            Text("\(model.pulls(in: tab).count)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(settingsTertiary)
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
                    if model.tab == .requested, model.hasTeamRequests {
                        FacetToggle(title: "Direct only", isOn: $model.directOnly,
                                    help: "Only reviews asked of you, not of your teams")
                    }
                    FacetMenu(title: "Repository", value: model.repo, options: model.repos, selection: $model.repo, mono: true)
                    if model.tab == .requested {
                        FacetMenu(title: "Author", value: model.author, options: model.authors, selection: $model.author, mono: true)
                    }
                    FacetMenu(title: "Checks", value: model.checks.map(Self.checksTitle),
                              options: [GitHubStatus.Checks.failing, .pending, .passing, .none], selection: $model.checks,
                              label: Self.checksTitle)
                    FacetToggle(title: "Hide drafts", isOn: $model.hideDrafts, help: "Leave out draft pull requests")
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
        case .return: model.openSelection(newTab: press.modifiers.contains(.command))
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
            column {
                if let error = github.lastError { errorLine(error).padding(.top, 16) } else { skeleton }
            }
            Spacer()
        } else {
            list
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

    /// Placeholder rows while the first fetch runs; static, so nothing moves.
    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(0..<6, id: \.self) { index in
                HStack(spacing: 10) {
                    Circle().fill(Color(nsColor: Theme.fieldFill)).frame(width: 12, height: 12)
                    RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: Theme.fieldFill))
                        .frame(width: [280, 220, 340, 190, 260, 300][index], height: 10)
                    Spacer()
                    HStack(spacing: 12) {
                        HStack(spacing: 6) {
                            Circle().fill(Color(nsColor: Theme.fieldFill)).frame(width: 16, height: 16)
                            RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: Theme.fieldFill)).frame(width: 56, height: 10)
                        }
                        .frame(width: 120, alignment: .leading)
                        RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: Theme.fieldFill)).frame(width: 52, height: 10)
                            .frame(width: 84, alignment: .trailing)
                        Circle().fill(Color(nsColor: Theme.fieldFill)).frame(width: 7, height: 7)
                        RoundedRectangle(cornerRadius: 3).fill(Color(nsColor: Theme.fieldFill)).frame(width: 20, height: 10)
                            .frame(width: 30, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 8).frame(height: 36)
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

    private var list: some View {
        let rows = model.rows
        return ScrollViewReader { proxy in
            ScrollView {
                column {
                    if let error = github.lastError { errorLine(error).padding(.bottom, 8) }
                    if rows.isEmpty {
                        emptyState.padding(.top, 16)
                    } else {
                        TimelineView(.periodic(from: .now, by: 60)) { context in
                            LazyVStack(spacing: 0) {
                                ForEach(rows) { pull in
                                    PullRow(pull: pull, tab: model.tab, filter: model.filter, isSelected: model.selection == pull.id,
                                            isCompact: isCompact, now: context.date, open: model.open)
                                        .id(pull.id)
                                }
                            }
                        }
                        footer
                    }
                }
                .padding(.top, 8).padding(.bottom, 40)
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
                    model.open(URL(string: "https://github.com/\(path)")!, NSApp.currentEvent?.modifierFlags.contains(.command) ?? false)
                }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(settingsSecondary)
            }
            .padding(.top, 16).padding(.horizontal, 8)
        }
    }
}

// MARK: Row

private struct PullRow: View {
    let pull: GitHubPull
    let tab: ReviewsModel.Tab
    let filter: PageFilter
    let isSelected: Bool
    let isCompact: Bool
    let now: Date
    let open: (URL, Bool) -> Void
    @State private var isHovered = false

    /// Tertiary text steps up to secondary on the selected row, so it clears 4.5:1 on the pressed fill.
    private var quiet: Color { isSelected ? settingsSecondary : settingsTertiary }

    var body: some View {
        HStack(spacing: 10) {
            stateGlyph
            HStack(spacing: 8) {
                Text(filter.highlight(pull.title, size: 13))
                    .font(.system(size: 13, weight: isSelected ? .medium : .regular)).foregroundStyle(settingsPrimary)
                    .lineLimit(1)
                // The reference is what an engineer copies, so the title truncates first.
                HStack(spacing: 0) {
                    Text(filter.highlight(pull.repo, size: 11, design: .monospaced)).foregroundStyle(settingsSecondary)
                    Text(verbatim: "#\(pull.number)").foregroundStyle(quiet)
                }
                .font(.system(size: 11, design: .monospaced)).lineLimit(1).fixedSize()
                if !isCompact, pull.isTeamRequest, let team = pull.requestedTeam {
                    HStack(spacing: 3) {
                        Image(systemName: "person.2").font(.system(size: 9, weight: .medium)).accessibilityHidden(true)
                        Text(filter.highlight(team, size: 11, design: .monospaced)).font(.system(size: 11, design: .monospaced)).lineLimit(1)
                    }
                    .foregroundStyle(quiet)
                    .help("Requested of the \(team) team")
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 8).frame(height: 36)
        // Keyboard selection sits one ramp step deeper than hover, so Return's target is never ambiguous.
        .background(RoundedRectangle(cornerRadius: 5).fill(
            isSelected ? Color(nsColor: Theme.pressedFill) : isHovered ? Color(nsColor: Theme.hoverFill) : .clear))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { open(pull.url, NSApp.currentEvent?.modifierFlags.contains(.command) ?? false) }
        .help(helpText)
        .contextMenu { menu }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(isSelected ? [.isLink, .isSelected] : .isLink)
        .accessibilityAction { open(pull.url, false) }
    }

    private var stateGlyph: some View {
        Group {
            if let image = GitHubStyle.image(pull.isDraft ? .draft : .open, size: 12) {
                Image(nsImage: image)
            }
        }
        .frame(width: 16)
    }

    private var trailing: some View {
        HStack(spacing: 12) {
            if tab == .requested {
                HStack(spacing: 6) {
                    AvatarView(url: pull.authorAvatarURL)
                    if !isCompact, let author = pull.author {
                        Text(filter.highlight(author, size: 11, design: .monospaced)).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(settingsSecondary).lineLimit(1)
                    }
                }
                .frame(width: isCompact ? 16 : 120, alignment: .leading)
            } else {
                reviewDecision.frame(width: isCompact ? 16 : 120, alignment: .leading)
            }
            if !isCompact {
                HStack(spacing: 4) {
                    Text(verbatim: "+\(pull.additions)")
                    Text(verbatim: "−\(pull.deletions)")
                }
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(quiet)
                .frame(width: 84, alignment: .trailing)
            }
            Circle().fill(Color(nsColor: GitHubStyle.color(pull.checks) ?? .clear)).frame(width: 7, height: 7)
                .help(GitHubStyle.label(pull.checks).map { $0.prefix(1).uppercased() + $0.dropFirst() } ?? "No checks")
            Text(pull.updatedAt.map { RelativeAge.short(since: $0, now: now) } ?? "")
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(quiet)
                .frame(width: 30, alignment: .trailing)
        }
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
        Button("Open in New Tab") { open(pull.url, true) }
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
        parts.append("\(pull.additions) additions, \(pull.deletions) deletions")
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
                        Text(value).font(.system(size: 12, weight: .medium, design: mono ? .monospaced : .default))
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

/// A facet that is on or off.
private struct FacetToggle: View {
    let title: String
    @Binding var isOn: Bool
    let help: String

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: 4) {
                if isOn { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(title)
            }
            .font(.system(size: 12, weight: isOn ? .medium : .regular))
            .foregroundStyle(isOn ? settingsPrimary : settingsSecondary)
            .padding(.horizontal, 8).frame(height: 24)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: isOn ? Theme.hoverFill : Theme.fieldFill)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityAddTraits(isOn ? .isSelected : [])
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
