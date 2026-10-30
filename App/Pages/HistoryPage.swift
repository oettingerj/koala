import AppKit
import BrowserKit
import SwiftUI

/// koala://history: every visited page by day, searchable, with deletes by page or by site.
@MainActor
@Observable
final class HistoryPageModel {
    var query = ""
    var focusRequest = 0
    private(set) var entries: [HistoryEntry] = []
    private(set) var hasMore = false
    @ObservationIgnored let open: (URL, _ newTab: Bool) -> Void
    private var history: HistoryStore { AppServices.shared.history }
    private static let pageSize = 200

    init(open: @escaping (URL, Bool) -> Void) { self.open = open }

    /// Searching shows the best 300 matches; browsing pages back 200 at a time.
    func reload() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        if text.isEmpty {
            entries = (try? await history.recent(limit: Self.pageSize)) ?? []
            hasMore = entries.count == Self.pageSize
        } else {
            entries = ((try? await history.search(text, limit: 300)) ?? []).sorted { $0.lastVisitedAt > $1.lastVisitedAt }
            hasMore = false
        }
    }

    func loadMore() async {
        let more = (try? await history.recent(limit: Self.pageSize, offset: entries.count)) ?? []
        entries += more
        hasMore = more.count == Self.pageSize
    }

    func delete(_ entry: HistoryEntry) async {
        try? await history.delete(entry)
        entries.removeAll { $0.id == entry.id }
    }

    func delete(host: String) async {
        try? await history.delete(host: host)
        entries.removeAll { $0.host == host }
    }

    /// Entries grouped by calendar day, newest day first.
    var days: [(day: Date, entries: [HistoryEntry])] {
        let calendar = Calendar.current
        var groups: [(day: Date, entries: [HistoryEntry])] = []
        for entry in entries {
            let day = calendar.startOfDay(for: entry.lastVisitedAt)
            if groups.last?.day == day { groups[groups.count - 1].entries.append(entry) } else { groups.append((day, [entry])) }
        }
        return groups
    }
}

final class HistoryHostingView: NSHostingView<HistoryPage>, SearchablePage {
    func focusSearch() { rootView.model.focusRequest += 1 }

    static func make(open: @escaping (URL, Bool) -> Void) -> HistoryHostingView {
        let view = HistoryHostingView(rootView: HistoryPage(model: HistoryPageModel(open: open)))
        view.sizingOptions = []
        return view
    }
}

struct HistoryPage: View {
    @Bindable var model: HistoryPageModel
    @FocusState private var searchFocused: Bool
    /// Bumped when history is cleared from the menu or Settings.
    private var revision: Int { AppServices.shared.historyRevision }

    var body: some View {
        VStack(spacing: 0) {
            PageColumn {
                HStack {
                    Text("History").font(.system(size: 20, weight: .semibold)).foregroundStyle(settingsPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("Clear History…") { NSApp.sendAction(#selector(AppDelegate.clearHistory(_:)), to: nil, from: nil) }
                }
                .padding(.bottom, 14)
                PageSearchField(prompt: "Search history", text: $model.query, focused: $searchFocused)
            }
            .padding(.top, 24).padding(.bottom, 12)
            SettingsRule()
            ScrollView {
                PageColumn {
                    if model.entries.isEmpty {
                        Text(model.query.isEmpty ? "Pages you visit appear here." : "No pages match “\(model.query)”.")
                            .font(.system(size: 13)).foregroundStyle(settingsSecondary)
                            .frame(maxWidth: .infinity).padding(.top, 48)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(model.days, id: \.day) { group in
                                Text(Self.dayTitle(group.day)).font(.system(size: 12, weight: .semibold)).foregroundStyle(settingsSecondary)
                                    .accessibilityAddTraits(.isHeader)
                                    .padding(.top, 20).padding(.bottom, 6)
                                ForEach(group.entries, id: \.id) { entry in HistoryRow(entry: entry, model: model) }
                            }
                            if model.hasMore {
                                Button("Show Older") { Task { await model.loadMore() } }
                                    .padding(.top, 16)
                            }
                        }
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .background(Color(nsColor: Theme.chromeSurface))
        .task(id: "\(model.query)|\(revision)") {
            try? await Task.sleep(for: .milliseconds(model.query.isEmpty ? 0 : 120))
            guard !Task.isCancelled else { return }
            await model.reload()
        }
        .onAppear { searchFocused = true }
        .onChange(of: model.focusRequest) { searchFocused = true }
    }

    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }
}

private struct HistoryRow: View {
    let entry: HistoryEntry
    let model: HistoryPageModel
    @State private var isHovered = false

    private var url: URL? { URL(string: entry.url) }

    var body: some View {
        HStack(spacing: 12) {
            Text(entry.lastVisitedAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 11).monospacedDigit()).foregroundStyle(settingsTertiary)
                .frame(width: 64, alignment: .leading)
            Text(entry.title.isEmpty ? entry.url : entry.title)
                .font(.system(size: 13)).foregroundStyle(settingsPrimary).lineLimit(1)
            Text(entry.host).font(.mono(size: 11)).foregroundStyle(settingsTertiary).lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 5).fill(isHovered ? Color(nsColor: Theme.hoverFill) : .clear))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            guard let url else { return }
            model.open(url, NSApp.currentEvent?.modifierFlags.contains(.command) ?? false)
        }
        .help(entry.url)
        .contextMenu {
            if let url {
                Button("Open in New Tab") { model.open(url, true) }
                Button("Copy Link") { Pasteboard.copy(url: url, title: entry.title) }
                Divider()
            }
            Button("Delete") { Task { await model.delete(entry) } }
            if !entry.host.isEmpty {
                Button("Delete All from \(entry.host)") { Task { await model.delete(host: entry.host) } }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isLink)
        .accessibilityAction { if let url { model.open(url, false) } }
    }
}
