import AppKit
import SwiftUI

/// A native page (Settings, History, Bookmarks) with a search field that ⌘F and opening the page focus.
@MainActor
protocol SearchablePage: NSView {
    func focusSearch()
}

/// A native page whose content ⌘R refreshes (Reviews), instead of reloading a web view.
@MainActor
protocol RefreshablePage: NSView {
    func refresh()
}

/// The search field native pages share. Esc clears it.
struct PageSearchField: View {
    let prompt: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    /// Arrow keys and Return, for pages whose list the field drives.
    var onKey: ((KeyPress) -> KeyPress.Result)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .medium)).foregroundStyle(settingsTertiary)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain).font(.system(size: 13))
                .tint(Color(nsColor: Theme.accent))
                .focused(focused)
                .accessibilityLabel(prompt)
                .onKeyPress(.escape) {
                    guard !text.isEmpty else { return .ignored }
                    text = ""
                    return .handled
                }
                .onKeyPress(keys: [.upArrow, .downArrow, .return]) { press in onKey?(press) ?? .ignored }
            if text.isEmpty {
                Text("⌘F").font(.system(size: 11).monospacedDigit()).foregroundStyle(settingsTertiary).accessibilityHidden(true)
            } else {
                Text("esc").font(.system(size: 11)).foregroundStyle(settingsTertiary).accessibilityHidden(true)
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 12)).foregroundStyle(settingsTertiary)
                }
                .buttonStyle(.plain).help("Clear search (Esc)").accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).frame(height: 32)
        .background(RoundedRectangle(cornerRadius: Theme.controlRadius)
            .fill(Color(nsColor: focused.wrappedValue ? Theme.neutral(0) : Theme.fieldFill)))
        .overlay {
            if focused.wrappedValue {
                RoundedRectangle(cornerRadius: Theme.controlRadius).strokeBorder(Color(nsColor: Theme.accent), lineWidth: 1.5)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { focused.wrappedValue = true }
    }
}

/// A page column up to `width` with 20pt gutters, centered.
struct PageColumn<Content: View>: View {
    var width: CGFloat = 760
    @ViewBuilder var content: Content
    @State private var pageWidth: CGFloat = 0

    var body: some View {
        let column = max(0, min(width, pageWidth - 40))
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(width: column, alignment: .leading)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { pageWidth = $0 }
    }
}

/// A native page's search query. Like the command bar, every query word must start a word in the row's text,
/// so "pin" finds Pin to Toolbar but not "typing".
struct PageFilter {
    var query = ""

    var words: [String] { Self.words(in: query) }
    var isActive: Bool { !words.isEmpty }

    private static func words(in text: String) -> [String] {
        text.lowercased().split { !$0.isLetter && !$0.isNumber && $0 != "%" }.map(String.init)
    }

    func matches(_ text: String) -> Bool {
        let haystack = Self.words(in: text)
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
