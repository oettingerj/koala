import AppKit
import SwiftUI

let devPrimary = Color(nsColor: Theme.textPrimary)
let devSecondary = Color(nsColor: Theme.textSecondary)
let devTertiary = Color(nsColor: Theme.textTertiary)

struct DevRule: View {
    var body: some View { Rectangle().fill(Color(nsColor: Theme.hairline)).frame(height: 1) }
}

struct DevIcon: View {
    let title: String
    let symbol: String
    var action: () -> Void
    init(_ title: String, symbol: String, action: @escaping () -> Void) { self.title = title; self.symbol = symbol; self.action = action }
    var body: some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 12)).frame(width: 26, height: 26).contentShape(Rectangle()) }
            .buttonStyle(.borderless).foregroundStyle(devSecondary).help(title).accessibilityLabel(title)
    }
}

struct DevEmpty: View {
    let title: String
    let detail: String
    var symbol = "text.magnifyingglass"
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(devTertiary).accessibilityHidden(true)
            Text(title).font(.system(size: 13, weight: .medium)).foregroundStyle(devPrimary)
            Text(detail).font(.system(size: 12)).foregroundStyle(devSecondary).multilineTextAlignment(.center).frame(maxWidth: 340)
        }.padding(20).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DevSearch: View {
    @Binding var text: String
    var prompt: String
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(devTertiary)
            TextField(prompt, text: $text).textFieldStyle(.plain).font(.system(size: 12)).accessibilityLabel(prompt)
            if !text.isEmpty { Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).accessibilityLabel("Clear search") }
        }.padding(.horizontal, 8).frame(minWidth: 100, idealWidth: 220, maxWidth: 300).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 5).fill(Color(nsColor: Theme.fieldFill)))
    }
}

struct DevToolbar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { ViewThatFits(in: .horizontal) {
        HStack(spacing: 10) { content }.fixedSize(horizontal: true, vertical: false)
        ScrollView(.horizontal) { HStack(spacing: 10) { content } }.scrollIndicators(.automatic)
    }.frame(maxWidth: .infinity, alignment: .leading)
        .font(.system(size: 11)).foregroundStyle(devSecondary).controlSize(.small).buttonStyle(.borderless).tint(devSecondary)
        .padding(.horizontal, 12).frame(height: 40) }
}

struct DevSplit<Items: View, Detail: View>: View {
    let hasSelection: Bool
    let clearSelection: () -> Void
    @ViewBuilder var items: Items
    @ViewBuilder var detail: Detail
    @AppStorage("DevToolsListFraction") private var fraction = 0.58
    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 760 {
                let width = geometry.size.width
                let left = max(300, min(width - 325, width * fraction))
                HStack(spacing: 0) {
                    items.frame(width: left, height: geometry.size.height).clipped()
                    Rectangle().fill(Color(nsColor: Theme.hairline)).frame(width: 1)
                        .frame(width: 5, height: geometry.size.height).contentShape(Rectangle())
                        .onHover { over in if over { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                        .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("devtools-split"))
                            .onChanged { fraction = max(300 / width, min(1 - 325 / width, $0.location.x / width)) })
                        .focusable().accessibilityLabel("Resize list and details")
                        .accessibilityValue("\(Int(fraction * 100)) percent list")
                        .accessibilityAdjustableAction { direction in
                            fraction = max(300 / width, min(1 - 325 / width, fraction + (direction == .increment ? 0.05 : -0.05)))
                        }
                        .onKeyPress(.leftArrow) { fraction = max(300 / width, fraction - 0.03); return .handled }
                        .onKeyPress(.rightArrow) { fraction = min(1 - 325 / width, fraction + 0.03); return .handled }
                    detail.frame(width: max(0, width - left - 5), height: geometry.size.height).clipped()
                }.coordinateSpace(name: "devtools-split")
            } else if hasSelection {
                VStack(spacing: 0) {
                    HStack { Button("Back to list", systemImage: "chevron.left", action: clearSelection).buttonStyle(.borderless); Spacer() }
                        .font(.system(size: 12)).padding(.horizontal, 12).frame(height: 30)
                    DevRule()
                    detail
                }
            } else { items }
        }
    }
}

struct DevCode: View {
    let text: String
    var body: some View {
        Text(text).font(.mono(size: 12)).lineSpacing(4).textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .foregroundStyle(devPrimary).frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Native virtualized rows with one selection treatment in active and inactive windows.
/// SwiftUI Table does not expose its selection fill; keeping ownership here also keeps data legible.
struct DevRows<Row: Identifiable, Header: View, Cell: View>: View {
    let rows: [Row]
    @Binding var selection: Row.ID?
    var focusRequest = 0
    @FocusState private var focused: Bool
    @ViewBuilder var header: Header
    @ViewBuilder var cell: (Row) -> Cell
    var body: some View {
        VStack(spacing: 0) {
            header.font(.system(size: 11, weight: .medium)).foregroundStyle(devSecondary)
                .padding(.horizontal, 12).frame(height: 26)
            DevRule()
            ScrollViewReader { proxy in
                List {
                    ForEach(rows) { row in
                        Button { selection = row.id } label: {
                            cell(row).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.buttonStyle(.plain).id(row.id)
                            .accessibilityAddTraits(selection == row.id ? .isSelected : [])
                            .listRowBackground(selection == row.id ? Color(nsColor: Theme.hoverFill) : .clear)
                            .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                            .listRowSeparatorTint(Color(nsColor: Theme.hairline))
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden).environment(\.defaultMinListRowHeight, 28)
                    .focusable().focused($focused)
                    .onChange(of: focusRequest) { _, _ in focused = true }
                    .onKeyPress(.downArrow) { move(1, proxy: proxy); return .handled }
                    .onKeyPress(.upArrow) { move(-1, proxy: proxy); return .handled }
            }
        }
    }
    private func move(_ step: Int, proxy: ScrollViewProxy) {
        guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0.id == selection }
        let next = index.map { max(0, min(rows.count - 1, $0 + step)) } ?? (step > 0 ? 0 : rows.count - 1)
        selection = rows[next].id
        proxy.scrollTo(rows[next].id)
    }
}

struct DevHeading: View {
    let title: String
    var action: String = "Copy"
    var copy: String?
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(devPrimary)
            Spacer()
            if let copy { Button(action) { devCopy(copy) }.buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(devSecondary) }
        }.fixedSize(horizontal: false, vertical: true)
    }
}

struct DevPairs: View {
    let rows: [(String, String)]
    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 9) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, pair in
                GridRow {
                    Text(pair.0).font(.mono(size: 11)).foregroundStyle(devSecondary)
                        .frame(minWidth: 80, maxWidth: 180, alignment: .leading).textSelection(.enabled)
                    DevCode(text: pair.1)
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

func devCopy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
func devMS(_ value: Double) -> String { value >= 1000 ? String(format: "%.2f s", value / 1000) : "\(Int(value.rounded())) ms" }
func devBytes(_ count: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file) }
func devPretty(_ text: String) -> String {
    guard let data = text.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
          let pretty = try? JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]),
          let result = String(data: pretty, encoding: .utf8) else { return text }
    return result
}
