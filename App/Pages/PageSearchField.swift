import AppKit
import SwiftUI

/// A native page (Settings, History, Bookmarks) with a search field that ⌘F and opening the page focus.
@MainActor
protocol SearchablePage: NSView {
    func focusSearch()
}

/// The search field native pages share. Esc clears it.
struct PageSearchField: View {
    let prompt: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

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
