import AppKit
import BrowserKit
import SwiftUI

/// koala://bookmarks: every folder and bookmark, to search, open, edit, move, and reorder.
@MainActor
@Observable
final class BookmarksPageModel {
    var query = ""
    var focusRequest = 0
    /// The folder shown on the right; nil is the bookmarks bar.
    var folderID: Int64?
    @ObservationIgnored let open: (URL, _ newTab: Bool) -> Void
    var library: BookmarkLibrary { AppServices.shared.bookmarks }

    init(open: @escaping (URL, Bool) -> Void) { self.open = open }

    /// The bar and every folder under it, depth first.
    var folders: [(folder: Bookmark?, depth: Int)] {
        var rows: [(folder: Bookmark?, depth: Int)] = [(nil, 0)]
        func add(_ parentID: Int64?, depth: Int) {
            for folder in library.children(of: parentID) where folder.isFolder {
                rows.append((folder, depth))
                add(folder.id, depth: depth + 1)
            }
        }
        add(nil, depth: 1)
        return rows
    }

    /// The selected folder's items, or every bookmark matching the search.
    var items: [Bookmark] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        guard !words.isEmpty else { return library.children(of: folderID) }
        return library.all.filter { bookmark in
            let text = (bookmark.title + " " + (bookmark.url ?? "")).lowercased()
            return words.allSatisfy(text.contains)
        }
    }

    func folderName(_ id: Int64?) -> String {
        id.flatMap { id in library.all.first { $0.id == id }?.title } ?? "Bookmarks Bar"
    }

    func moveBy(_ bookmark: Bookmark, _ offset: Int) {
        let siblings = library.children(of: bookmark.parentID)
        guard let index = siblings.firstIndex(where: { $0.id == bookmark.id }) else { return }
        Task { try? await library.move(bookmark, to: index + offset, in: bookmark.parentID) }
    }
}

final class BookmarksHostingView: NSHostingView<BookmarksPage>, SearchablePage {
    func focusSearch() { rootView.model.focusRequest += 1 }

    static func make(open: @escaping (URL, Bool) -> Void) -> BookmarksHostingView {
        let view = BookmarksHostingView(rootView: BookmarksPage(model: BookmarksPageModel(open: open)))
        view.sizingOptions = []
        return view
    }
}

struct BookmarksPage: View {
    @Bindable var model: BookmarksPageModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            PageColumn(width: 960) {
                HStack {
                    Text("Bookmarks").font(.system(size: 20, weight: .semibold)).foregroundStyle(settingsPrimary)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button("New Folder…") {
                        guard let window = NSApp.keyWindow else { return }
                        BookmarkMenus.newFolder(in: model.folderID, library: model.library, in: window)
                    }
                }
                .padding(.bottom, 14)
                PageSearchField(prompt: "Search bookmarks", text: $model.query, focused: $searchFocused)
            }
            .padding(.top, 24).padding(.bottom, 12)
            SettingsRule()
            PageColumn(width: 960) {
                HStack(alignment: .top, spacing: 24) {
                    ScrollView { folderList.padding(.vertical, 16) }
                        .frame(width: 220)
                    ScrollView { itemList.padding(.vertical, 16) }
                }
            }
        }
        .background(Color(nsColor: Theme.chromeSurface))
        .onAppear { searchFocused = true }
        .onChange(of: model.focusRequest) { searchFocused = true }
    }

    private var folderList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(model.folders, id: \.folder?.id) { row in
                let isCurrent = model.query.isEmpty && model.folderID == row.folder?.id
                Button { model.folderID = row.folder?.id; model.query = "" } label: {
                    HStack(spacing: 6) {
                        Image(systemName: row.folder == nil ? "menubar.rectangle" : "folder")
                            .font(.system(size: 12)).foregroundStyle(settingsTertiary).accessibilityHidden(true)
                        Text(row.folder?.title ?? "Bookmarks Bar").lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                    .foregroundStyle(isCurrent ? settingsPrimary : settingsSecondary)
                    .padding(.leading, 8 + CGFloat(max(0, row.depth - 1)) * 14).padding(.trailing, 8).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 5).fill(isCurrent ? Color(nsColor: Theme.hoverFill) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isCurrent ? .isSelected : [])
            }
        }
    }

    private var itemList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.query.isEmpty ? model.folderName(model.folderID) : "Search results")
                .font(.system(size: 12, weight: .semibold)).foregroundStyle(settingsSecondary)
                .accessibilityAddTraits(.isHeader)
                .padding(.bottom, 8)
            let items = model.items
            if items.isEmpty {
                Text(model.query.isEmpty ? "This folder is empty." : "No bookmarks match “\(model.query)”.")
                    .font(.system(size: 13)).foregroundStyle(settingsSecondary).padding(.top, 8)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { index, bookmark in
                BookmarkRow(bookmark: bookmark, model: model, isFirst: index == 0, isLast: index == items.count - 1)
            }
        }
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark
    let model: BookmarksPageModel
    let isFirst: Bool
    let isLast: Bool
    @State private var isHovered = false

    private var url: URL? { bookmark.url.flatMap(URL.init(string:)) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: bookmark.isFolder ? "folder" : "globe")
                .font(.system(size: 12)).foregroundStyle(settingsTertiary).frame(width: 16).accessibilityHidden(true)
            Text(bookmark.title.isEmpty ? (bookmark.url ?? "Untitled") : bookmark.title)
                .font(.system(size: 13)).foregroundStyle(settingsPrimary).lineLimit(1)
            if let url {
                Text(DisplayURL(url).map { $0.host + $0.remainder } ?? url.absoluteString)
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(settingsTertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 8).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 5).fill(isHovered ? Color(nsColor: Theme.hoverFill) : .clear))
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if bookmark.isFolder {
                model.folderID = bookmark.id
                model.query = ""
            } else if let url {
                model.open(url, NSApp.currentEvent?.modifierFlags.contains(.command) ?? false)
            }
        }
        .help(bookmark.url ?? bookmark.title)
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(bookmark.isFolder ? .isButton : .isLink)
    }

    @ViewBuilder private var menu: some View {
        if let url {
            Button("Open in New Tab") { model.open(url, true) }
            Button("Copy Link") { Pasteboard.copy(url: url, title: bookmark.title) }
            Divider()
        }
        Button(bookmark.isFolder ? "Rename…" : "Edit…") {
            if let window = NSApp.keyWindow { BookmarkMenus.edit(bookmark, library: model.library, in: window) }
        }
        Menu("Move To") {
            ForEach(model.folders, id: \.folder?.id) { row in
                let parentID = row.folder?.id
                if model.library.canMove(bookmark, into: parentID), parentID != bookmark.parentID {
                    Button(String(repeating: "    ", count: row.depth) + (row.folder?.title ?? "Bookmarks Bar")) {
                        let end = model.library.children(of: parentID).count
                        Task { try? await model.library.move(bookmark, to: end, in: parentID) }
                    }
                }
            }
        }
        if model.query.isEmpty {
            Button("Move Up") { model.moveBy(bookmark, -1) }.disabled(isFirst)
            Button("Move Down") { model.moveBy(bookmark, 1) }.disabled(isLast)
        }
        Divider()
        Button("Delete") { BookmarkMenus.delete(bookmark, library: model.library, in: NSApp.keyWindow) }
    }
}
