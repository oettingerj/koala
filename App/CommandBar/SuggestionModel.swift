import AppKit
import BrowserKit
import Observation

/// State behind the command bar and the address field dropdown: the query, its rows, and
/// which row is highlighted. Remote rows stream in below local ones, each source as soon as it
/// answers, and never move the highlight.
@MainActor
@Observable
final class SuggestionModel {
    private(set) var rows: [Suggestion] = []
    var selectedIndex = 0 {
        didSet {
            // Leaving the completion's row takes the completion out of the field, so the
            // field never shows one address while Return opens another.
            if inline != nil, selected?.inline == nil {
                inline = nil
                onLeaveCompletion?()
            }
            loadFacts()
        }
    }
    /// The completion the field shows ahead of the caret, from the top row.
    private(set) var inline: InlineCompletion?
    /// Called when the selection moves off the completion's row.
    @ObservationIgnored var onLeaveCompletion: (() -> Void)?
    /// Completions deleted during this edit; they don't come back until it ends.
    @ObservationIgnored private var rejectedCompletions: Set<String> = []
    private(set) var icons: [String: NSImage] = [:]
    private(set) var query = ""
    /// What the preview pane knows about the highlighted row beyond the row itself.
    private(set) var facts: PreviewFacts?

    /// Set by the panel while its preview pane shows; facts are only read when someone looks.
    @ObservationIgnored var loadsFacts = false {
        didSet { if loadsFacts != oldValue { loadFacts() } }
    }

    @ObservationIgnored let engine: SuggestionEngine
    @ObservationIgnored private var remoteTask: Task<Void, Never>?
    @ObservationIgnored private var factsTask: Task<Void, Never>?
    @ObservationIgnored private var iconRequests: Set<String> = []

    /// Streamed rows per section, so GitHub matches can't crowd out History.
    private static let remoteLimits: [Suggestion.Section: Int] = [.github: 3, .history: 4, .suggestions: 4]
    /// Where the pointer was when rows last changed under it; see `hover(at:)`.
    @ObservationIgnored private var pointerAtLastChange = NSEvent.mouseLocation

    init(engine: SuggestionEngine) {
        self.engine = engine
    }

    var selected: Suggestion? {
        rows.indices.contains(selectedIndex) ? rows[selectedIndex] : nil
    }

    func update(query: String, edit: TextEdit = .other) {
        self.query = query
        remoteTask?.cancel()
        pointerAtLastChange = NSEvent.mouseLocation
        if edit == .deleted, let shown = inline { rejectedCompletions.insert(shown.key) }
        let completion = CompletionContext(enabled: edit == .typed, current: inline?.key, suppressed: rejectedCompletions)
        inline = nil
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            rows = engine.zeroStateResults()
            selectedIndex = 0
            loadDetails(for: rows)
            return
        }
        let local = Perf.measure("suggestions.local") { engine.localResults(for: query, completion: completion) }
        let selectedID = selected?.id
        rows = local
        inline = local.first?.inline
        // A completion is what Return opens; otherwise keep the highlight on the same row while
        // typing refines the list, else the top row.
        selectedIndex = inline != nil ? 0 : selectedID.flatMap { id in local.firstIndex { $0.id == id } } ?? 0
        if selectedIndex != 0 && query.count <= 1 { selectedIndex = 0 }
        loadDetails(for: local)

        remoteTask = Task { [weak self, engine] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            await withTaskGroup(of: [Suggestion].self) { group in
                for source in engine.remoteSources(for: query) {
                    group.addTask { await source() }
                }
                for await batch in group {
                    guard !Task.isCancelled, let self, self.query == query else { return group.cancelAll() }
                    self.merge(batch)
                }
            }
        }
    }

    /// Places a source's rows at the end of their sections, so a source that answers late
    /// (GitHub search) slots in above ones that answered early without reordering them.
    private func merge(_ batch: [Suggestion]) {
        let selectedID = selected?.id
        var seen = Set(rows.map(\.id))
        var additions: [Suggestion] = []
        for row in batch where seen.insert(row.id).inserted {
            guard rows.count(where: { $0.section == row.section }) < Self.remoteLimits[row.section, default: 4] else { continue }
            rows.insert(row, at: rows.firstIndex { $0.section > row.section } ?? rows.endIndex)
            additions.append(row)
        }
        guard !additions.isEmpty else { return }
        pointerAtLastChange = NSEvent.mouseLocation
        if let selectedID, let index = rows.firstIndex(where: { $0.id == selectedID }), index != selectedIndex {
            selectedIndex = index
        }
        loadDetails(for: additions)
    }

    func reset() {
        remoteTask?.cancel()
        inline = nil
        rejectedCompletions = []
        query = ""
        rows = []
        selectedIndex = 0
    }

    /// Pointer hover selects a row only when the pointer actually moved. Rows that grow, stream
    /// in, or scroll under a resting pointer report hover too, and must not move the highlight.
    func hover(at index: Int) {
        let location = NSEvent.mouseLocation
        guard location != pointerAtLastChange else { return }
        pointerAtLastChange = location
        selectedIndex = index
    }

    /// Keyboard scrolling moves rows under the pointer without it moving.
    func noteScrolled() {
        pointerAtLastChange = NSEvent.mouseLocation
    }

    func moveSelection(by step: Int) {
        guard !rows.isEmpty else { return }
        selectedIndex = (selectedIndex + step + rows.count) % rows.count
    }

    // MARK: Layout

    /// Whether row `index` opens a new section, which then gets a header.
    func startsSection(at index: Int) -> Bool {
        guard rows.indices.contains(index), rows[index].section.title != nil else { return false }
        return index == 0 || rows[index - 1].section != rows[index].section
    }

    /// Height of the rows and section headers, before any cap.
    var contentHeight: CGFloat {
        guard !rows.isEmpty else { return 0 }
        let headers = rows.indices.filter(startsSection(at:)).count
        return CGFloat(rows.count) * SuggestionMetrics.rowHeight + CGFloat(headers) * SuggestionMetrics.headerHeight
            + SuggestionMetrics.listInset * 2
    }

    /// Height of the list area in a panel, scrolled beyond the cap.
    func listHeight(showingPreview: Bool) -> CGFloat {
        guard !rows.isEmpty else { return 0 }
        let height = min(contentHeight, SuggestionMetrics.maxListHeight)
        return showingPreview ? max(height, SuggestionMetrics.previewMinHeight) : height
    }

    // MARK: Preview facts

    private func loadFacts() {
        guard loadsFacts, let row = selected else {
            factsTask?.cancel()
            facts = nil
            return
        }
        guard facts?.id != row.id else { return }
        factsTask?.cancel()
        var known = PreviewFacts(id: row.id)
        guard let url = row.pageURL else {
            facts = known
            return
        }
        known.isOpenInTab = row.kind != .tab && engine.tabs().contains { $0.url == url }
        known.folderPath = engine.bookmarkFolderPath(for: url)
        known.visitCount = row.visitCount
        known.lastVisitedAt = row.lastVisitedAt
        facts = known
        guard row.visitCount == nil else {
            facts?.visitsLoaded = true
            return
        }
        factsTask = Task { [weak self] in
            let history = AppServices.shared.history
            var entry = await history.entry(for: url)
            // A bare host ("https://github.com") is recorded with its root path.
            if entry == nil, url.path.isEmpty, let root = URL(string: url.absoluteString + "/") {
                entry = await history.entry(for: root)
            }
            guard !Task.isCancelled, let self, self.facts?.id == row.id else { return }
            self.facts?.visitCount = entry?.visitCount
            self.facts?.lastVisitedAt = entry?.lastVisitedAt
            self.facts?.visitsLoaded = true
        }
    }

    // MARK: Icons and GitHub state

    private func loadDetails(for rows: [Suggestion]) {
        loadIcons(for: rows)
        GitHubService.shared.ensureStatus(for: rows.compactMap(\.pageURL))
    }

    /// Favicons for each row: the host's cached icon, else its parent domain's
    /// (api.github.com shows GitHub's), else `/favicon.ico` fetched for hosts already visited.
    private func loadIcons(for rows: [Suggestion]) {
        for host in Set(rows.compactMap(\.iconHost)) where icons[host] == nil && !iconRequests.contains(host) {
            iconRequests.insert(host)
            let fetchable = engine.isKnownHost(host)
            Task { [weak self] in
                let favicons = AppServices.shared.favicons
                var data = await favicons.cached(host: host)
                if data == nil, let parent = Self.parentDomain(of: host) { data = await favicons.cached(host: parent) }
                if data == nil, fetchable, let url = Self.faviconURL(for: host) {
                    data = await favicons.icon(host: host, candidates: [url])
                }
                guard let data, let image = AppServices.image(data) else { return }
                self?.icons[host] = image
            }
        }
    }

    nonisolated static func parentDomain(of host: String) -> String? {
        let labels = host.split(separator: ".")
        guard labels.count >= 3, !host.contains(":"), Int(labels.last ?? "") == nil else { return nil }
        return labels.dropFirst().joined(separator: ".")
    }

    /// Hosts with a port are local servers, which rarely speak TLS.
    nonisolated static func faviconURL(for host: String) -> URL? {
        URL(string: "\(host.contains(":") ? "http" : "https")://\(host)/favicon.ico")
    }
}

/// Facts about the highlighted row that the row itself doesn't carry.
struct PreviewFacts: Equatable {
    var id: String
    var visitCount: Int?
    var lastVisitedAt: Date?
    var visitsLoaded = false
    var folderPath: String?
    var isOpenInTab = false
}

enum SuggestionMetrics {
    static let rowHeight: CGFloat = 40
    static let headerHeight: CGFloat = 30
    static let listInset: CGFloat = 6
    static let maxListHeight: CGFloat = 520
    static let previewWidth: CGFloat = 288
    static let previewMinHeight: CGFloat = 232
    /// Panels narrower than this show the list alone.
    static let previewThreshold: CGFloat = 720
}

extension Suggestion {
    /// The web page the row stands for, if any.
    var pageURL: URL? {
        var url: URL?
        if case .open(let target) = action, kind != .search, kind != .web, kind != .keyword { url = target }
        if url == nil { url = subtitle.flatMap(URL.init(string:)) }
        return url?.scheme?.hasPrefix("http") == true ? url : nil
    }
}
