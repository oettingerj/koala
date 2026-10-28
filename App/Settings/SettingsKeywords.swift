import AppKit
import BrowserKit
import SwiftUI

/// A keyword search being edited. `KeywordSearch` is identified by its keyword, which changes
/// as it is typed, so rows keep their own identity.
struct KeywordDraft: Identifiable, Equatable {
    let id = UUID()
    var search: KeywordSearch

    static func isUsable(_ search: KeywordSearch) -> Bool {
        !search.keyword.isEmpty && !search.keyword.contains(where: \.isWhitespace) && search.template.contains("%s")
    }
}

struct KeywordSettings: View {
    @Bindable var model: SettingsModel
    @Environment(\.settingsFilter) private var filter

    static func entry(for draft: KeywordDraft) -> SettingEntry {
        SettingEntry(id: draft.id.uuidString, section: .keywords, title: displayName(draft),
                     detail: draft.search.template, terms: [draft.search.keyword])
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach($model.keywords) { $draft in
                KeywordRow(draft: $draft, issue: issue(for: draft), isExpanded: model.expandedKeyword == draft.id,
                           focusesKeyword: model.focusesKeyword == draft.id) {
                    model.expandedKeyword = model.expandedKeyword == draft.id ? nil : draft.id
                    model.focusesKeyword = nil
                } onRemove: {
                    model.keywords.removeAll { $0.id == draft.id }
                }
            }
            if !filter.isActive {
                HStack(spacing: 8) {
                    Button(action: model.addKeyword) {
                        Label("Add Keyword", systemImage: "plus")
                    }
                    Spacer()
                    Button("Restore Defaults") {
                        model.keywords = KeywordSearch.defaults.map { KeywordDraft(search: $0) }
                        model.expandedKeyword = nil
                    }
                    .disabled(model.keywords.map(\.search) == KeywordSearch.defaults)
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { SettingsRule() }
            }
        }
    }

    static func displayName(_ draft: KeywordDraft) -> String {
        draft.search.name.isEmpty ? "Untitled search" : draft.search.name
    }

    /// Why a keyword won't work yet. Keywords with an issue are not saved.
    private func issue(for draft: KeywordDraft) -> String? {
        let keyword = draft.search.keyword
        if keyword.isEmpty { return "Add the keyword you’ll type before a search." }
        if keyword.contains(where: \.isWhitespace) { return "Keywords can’t contain spaces." }
        if !draft.search.template.contains("%s") { return "The URL needs %s where the search goes." }
        if let other = model.keywords.first(where: { $0.id != draft.id && $0.search.keyword.lowercased() == keyword.lowercased() }) {
            return "“\(keyword)” is also the keyword for \(other.search.name.isEmpty ? "another search" : other.search.name)."
        }
        return nil
    }
}

private struct KeywordRow: View {
    @Binding var draft: KeywordDraft
    let issue: String?
    let isExpanded: Bool
    let focusesKeyword: Bool
    let onToggle: () -> Void
    let onRemove: () -> Void
    @FocusState private var keywordFocused: Bool

    var body: some View {
        SettingsRowFrame(KeywordSettings.entry(for: draft)) {
            VStack(alignment: .leading, spacing: 12) {
                Button(action: onToggle) { summary }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(draft.search.name), keyword \(draft.search.keyword)")
                    .accessibilityHint(isExpanded ? "Collapses the editor" : "Edits this keyword")
                if isExpanded { editor }
            }
        }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            KeywordChip(keyword: draft.search.keyword)
            VStack(alignment: .leading, spacing: 3) {
                SettingTitle(KeywordSettings.displayName(draft))
                TemplateText(template: draft.search.template)
            }
            Spacer(minLength: 16)
            if let issue, !isExpanded {
                Image(systemName: "exclamationmark.circle.fill").font(.system(size: 12)).foregroundStyle(settingsFail)
                    .help(issue).accessibilityLabel(issue)
            }
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(settingsTertiary)
                .frame(width: 12).accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    label("Keyword")
                    TextField("gh", text: $draft.search.keyword)
                        .font(.system(size: 12, design: .monospaced))
                        .focused($keywordFocused)
                        .frame(maxWidth: 140)
                        .gridColumnAlignment(.leading)
                }
                GridRow {
                    label("Name")
                    TextField("GitHub", text: $draft.search.name)
                }
                GridRow {
                    label("URL")
                    TextField("https://github.com/search?q=%s", text: $draft.search.template)
                        .font(.system(size: 12, design: .monospaced))
                }
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit { if issue == nil { onToggle() } }
            HStack(spacing: 12) {
                if let issue {
                    Text(issue).foregroundStyle(settingsFail)
                } else if let example = draft.search.url(for: "view transitions") {
                    Text("“\(draft.search.keyword) view transitions” opens \(example.absoluteString)")
                        .foregroundStyle(settingsTertiary).lineLimit(1).truncationMode(.middle)
                }
                Spacer(minLength: 16)
                Button("Remove", role: .destructive, action: onRemove)
                if issue == nil { Button("Done", action: onToggle) }
            }
            .font(.system(size: 11))
        }
        .padding(.leading, KeywordChip.width + 12)
        .onAppear { if focusesKeyword { keywordFocused = true } }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 12)).foregroundStyle(settingsSecondary).gridColumnAlignment(.trailing)
    }
}

/// The keyword as it's typed, in a field-well chip.
private struct KeywordChip: View {
    static let width: CGFloat = 64
    let keyword: String
    @Environment(\.settingsFilter) private var filter

    var body: some View {
        Text(filter.highlight(keyword.isEmpty ? "—" : keyword, size: 12, design: .monospaced))
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundStyle(keyword.isEmpty ? settingsTertiary : settingsPrimary)
            .lineLimit(1).truncationMode(.tail)
            .padding(.horizontal, 6).frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: Theme.fieldFill)))
            .frame(width: Self.width, alignment: .leading)
    }
}

/// A search URL read host first: host in secondary, the rest in tertiary, scheme and "www." dropped.
private struct TemplateText: View {
    let template: String
    @Environment(\.settingsFilter) private var filter

    var body: some View {
        Text(attributed)
            .font(.system(size: 11, design: .monospaced))
            .lineLimit(1).truncationMode(.middle)
            .help(template)
    }

    private var attributed: AttributedString {
        var rest = Substring(template)
        for prefix in ["https://", "http://"] where rest.hasPrefix(prefix) { rest = rest.dropFirst(prefix.count) }
        if rest.hasPrefix("www.") { rest = rest.dropFirst(4) }
        let split = rest.firstIndex { $0 == "/" || $0 == "?" } ?? rest.endIndex
        var host = filter.highlight(String(rest[..<split]), size: 11, design: .monospaced)
        host.foregroundColor = settingsSecondary
        var remainder = filter.highlight(String(rest[split...]), size: 11, design: .monospaced)
        remainder.foregroundColor = settingsTertiary
        return host + remainder
    }
}
