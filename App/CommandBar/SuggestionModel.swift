import AppKit
import BrowserKit
import Observation

/// State behind the command bar and the address field dropdown: the query, its rows, and
/// which row is highlighted. Remote rows append below local ones and never move the highlight.
@MainActor
@Observable
final class SuggestionModel {
    private(set) var rows: [Suggestion] = []
    var selectedIndex = 0
    private(set) var icons: [String: NSImage] = [:]
    private(set) var query = ""

    @ObservationIgnored let engine: SuggestionEngine
    @ObservationIgnored private var remoteTask: Task<Void, Never>?
    @ObservationIgnored private var iconRequests: Set<String> = []

    init(engine: SuggestionEngine) {
        self.engine = engine
    }

    var selected: Suggestion? {
        rows.indices.contains(selectedIndex) ? rows[selectedIndex] : nil
    }

    func update(query: String) {
        self.query = query
        remoteTask?.cancel()
        let local = engine.localResults(for: query)
        let selectedID = selected?.id
        rows = local
        // Keep the highlight on the same row while typing refines the list, else the top row.
        selectedIndex = selectedID.flatMap { id in local.firstIndex { $0.id == id } } ?? 0
        if selectedIndex != 0 && query.count <= 1 { selectedIndex = 0 }
        loadIcons(for: local)

        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        remoteTask = Task { [weak self, engine] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let remote = await engine.remoteResults(for: query)
            guard !Task.isCancelled, let self, self.query == query else { return }
            let existing = Set(self.rows.map(\.id))
            let additions = remote.filter { !existing.contains($0.id) }
            self.rows.append(contentsOf: additions.prefix(max(0, 12 - self.rows.count)))
            self.loadIcons(for: additions)
        }
    }

    func reset() {
        remoteTask?.cancel()
        query = ""
        rows = []
        selectedIndex = 0
    }

    func moveSelection(by step: Int) {
        guard !rows.isEmpty else { return }
        selectedIndex = (selectedIndex + step + rows.count) % rows.count
    }

    private func loadIcons(for rows: [Suggestion]) {
        for host in Set(rows.compactMap(\.iconHost)) where icons[host] == nil && !iconRequests.contains(host) {
            iconRequests.insert(host)
            Task { [weak self] in
                guard let data = await AppServices.shared.favicons.cached(host: host),
                      let image = AppServices.image(data) else { return }
                self?.icons[host] = image
            }
        }
    }
}
