import AppKit
import BrowserKit
import SwiftUI
import WebKit

/// Which tab the dev panel is showing, plus storage read on demand.
@MainActor
@Observable
final class DevPanelModel {
    enum Section: String, CaseIterable, Identifiable {
        case console = "Console", network = "Network", storage = "Storage", page = "Page"
        var id: String { rawValue }
    }

    var tab: BrowserKit.Tab?
    var section: Section = .console
    var cookies: [HTTPCookie] = []
    var localStorage: [(String, String)] = []
    var sessionStorage: [(String, String)] = []

    /// Page-tool actions handled by the window controller.
    var perform: (PageAction) -> Void = { _ in }

    enum PageAction {
        case viewSource, copyScreenshot, savePDF, hardReload, clearSiteData, close
    }

    func refreshStorage() {
        guard let webView = tab?.webView, let host = tab?.url?.host() else {
            cookies = []; localStorage = []; sessionStorage = []
            return
        }
        Task {
            let all = await webView.configuration.websiteDataStore.httpCookieStore.allCookies()
            cookies = all.filter { cookie in
                let domain = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                return host == domain || host.hasSuffix("." + domain)
            }.sorted { $0.name < $1.name }
        }
        webView.evaluateJavaScript(DevToolsScripts.readStorage, in: nil, in: DevToolsScripts.world) { [weak self] (result: Result<Any, any Error>) in
            guard case .success(let value) = result, let dict = value as? [String: Any] else { return }
            func pairs(_ key: String) -> [(String, String)] {
                ((dict[key] as? [String: String]) ?? [:]).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
            }
            MainActor.assumeIsolated {
                self?.localStorage = pairs("local")
                self?.sessionStorage = pairs("session")
            }
        }
    }

    func delete(_ cookie: HTTPCookie) {
        guard let store = tab?.webView?.configuration.websiteDataStore.httpCookieStore else { return }
        Task {
            await store.deleteCookie(cookie)
            refreshStorage()
        }
    }
}

struct DevPanel: View {
    @Bindable var model: DevPanelModel

    static func host(model: DevPanelModel) -> NSView {
        NSHostingView(rootView: DevPanel(model: model))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Color(nsColor: Theme.hairline))
            Group {
                if let tab = model.tab {
                    switch model.section {
                    case .console: ConsoleView(record: tab.devTools)
                    case .network: NetworkView(record: tab.devTools)
                    case .storage: StorageView(model: model)
                    case .page: PageView(model: model, tab: tab)
                    }
                } else {
                    Text("No page").foregroundStyle(Color(nsColor: Theme.textTertiary))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .background(Color(nsColor: Theme.chromeSurface))
        .tint(Color(nsColor: Theme.accent))
        .onChange(of: model.section) { _, section in if section == .storage { model.refreshStorage() } }
    }

    private var header: some View {
        HStack(spacing: 2) {
            ForEach(DevPanelModel.Section.allCases) { section in
                Button { model.section = section } label: {
                    HStack(spacing: 4) {
                        Text(section.rawValue)
                        if section == .console, let count = model.tab?.devTools.errorCount, count > 0 {
                            Text("\(count)").font(.system(size: 10, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Color(nsColor: Theme.fail))
                        }
                    }
                    .font(.system(size: 12, weight: model.section == section ? .medium : .regular))
                    .foregroundStyle(Color(nsColor: model.section == section ? Theme.textPrimary : Theme.textSecondary))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(model.section == section ? Color(nsColor: Theme.hoverFill) : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Button { model.perform(.close) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(nsColor: Theme.textSecondary)).frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Close Dev Panel (⌥⌘J)")
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
    }
}

// MARK: Console

private struct ConsoleView: View {
    let record: DevToolsRecord
    @State private var filter = ""
    @State private var levels: Set<ConsoleEntry.Level> = Set(ConsoleEntry.Level.allCases)

    private var entries: [ConsoleEntry] {
        record.console.filter { levels.contains($0.level) && (filter.isEmpty || $0.text.localizedCaseInsensitiveContains(filter)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FilterField(text: $filter, prompt: "Filter messages")
                ForEach([ConsoleEntry.Level.error, .warn, .info, .log], id: \.self) { level in
                    Toggle(level.rawValue.capitalized, isOn: Binding(
                        get: { levels.contains(level) },
                        set: { on in if on { levels.insert(level) } else { levels.remove(level) } }))
                        .toggleStyle(.button).controlSize(.small)
                }
                Button("Clear") { record.clearConsole() }.controlSize(.small)
                Spacer()
            }
            .padding(8)
            ScrollViewReader { proxy in
                List(entries) { entry in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: glyph(entry.level)).font(.system(size: 10))
                            .foregroundStyle(color(entry.level)).frame(width: 12)
                        Text(entry.text).font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(entry.level == .error ? Color(nsColor: Theme.fail) : Color(nsColor: Theme.textPrimary))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if !entry.source.isEmpty {
                            Text(URL(string: entry.source)?.lastPathComponent ?? entry.source)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(Color(nsColor: Theme.textTertiary)).lineLimit(1)
                                .help(entry.source)
                        }
                    }
                    .id(entry.id)
                    .listRowSeparatorTint(Color(nsColor: Theme.hairline))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .onChange(of: record.console.last?.id) { _, id in if let id { proxy.scrollTo(id, anchor: .bottom) } }
                .overlay {
                    if entries.isEmpty { EmptyNote("No console messages") }
                }
            }
        }
    }

    private func glyph(_ level: ConsoleEntry.Level) -> String {
        switch level {
        case .error: "xmark.octagon.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .info: "info.circle"
        case .log, .debug: "chevron.right"
        }
    }

    private func color(_ level: ConsoleEntry.Level) -> Color {
        switch level {
        case .error: Color(nsColor: Theme.fail)
        case .warn: Color(nsColor: Theme.pending)
        default: Color(nsColor: Theme.textTertiary)
        }
    }
}

// MARK: Network

private struct NetworkView: View {
    let record: DevToolsRecord
    @State private var filter = ""

    private var entries: [ResourceEntry] {
        filter.isEmpty ? record.resources : record.resources.filter { $0.url.localizedCaseInsensitiveContains(filter) || $0.type == filter }
    }

    var body: some View {
        let rows = entries
        // One shared time scale: a bar's length is exactly its duration.
        let end = max(1, rows.map { $0.start + $0.duration }.max() ?? 1)
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                FilterField(text: $filter, prompt: "Filter URLs")
                Text("\(rows.count) requests · \(bytes(rows.reduce(0) { $0 + $1.transferSize })) · \(ms(end))")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(Color(nsColor: Theme.textTertiary))
                Spacer()
            }
            .padding(8)
            List(rows) { entry in
                HStack(spacing: 10) {
                    Text(label(entry.url)).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        .frame(width: 280, alignment: .leading).help(entry.url)
                    Text(entry.status == 0 ? "–" : "\(entry.status)")
                        .foregroundStyle(entry.status >= 400 ? Color(nsColor: Theme.fail) : Color(nsColor: Theme.textSecondary))
                        .frame(width: 32, alignment: .trailing)
                    Text(entry.type).foregroundStyle(Color(nsColor: Theme.textTertiary)).frame(width: 70, alignment: .leading)
                    Text(entry.transferSize == 0 ? "cached" : bytes(entry.transferSize))
                        .foregroundStyle(Color(nsColor: Theme.textTertiary)).frame(width: 64, alignment: .trailing)
                    Text(ms(entry.duration)).frame(width: 60, alignment: .trailing)
                    GeometryReader { geo in
                        Rectangle()
                            .fill(Color(nsColor: entry.status >= 400 ? Theme.fail : Theme.neutral(6)))
                            .frame(width: max(1, geo.size.width * entry.duration / end), height: 6)
                            .offset(x: geo.size.width * entry.start / end, y: (geo.size.height - 6) / 2)
                    }
                }
                .font(.system(size: 11).monospacedDigit())
                .frame(height: 18)
                .listRowSeparatorTint(Color(nsColor: Theme.hairline))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .overlay { if rows.isEmpty { EmptyNote("Reload the page to record its requests") } }
        }
    }

    private func label(_ url: String) -> String {
        guard let components = URL(string: url) else { return url }
        let path = components.path.isEmpty ? "/" : components.path
        return (components.host() ?? "") + path
    }
}

// MARK: Storage

private struct StorageView: View {
    @Bindable var model: DevPanelModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle("Cookies", count: model.cookies.count) {
                    Button("Refresh") { model.refreshStorage() }.controlSize(.small)
                }
                if model.cookies.isEmpty { EmptyNote("No cookies for this site").frame(height: 40) }
                ForEach(model.cookies, id: \.self) { cookie in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(cookie.name).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(width: 180, alignment: .leading)
                        Text(cookie.value).font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        Text(flags(cookie)).font(.system(size: 11)).foregroundStyle(Color(nsColor: Theme.textTertiary))
                        Button { model.delete(cookie) } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("Delete cookie")
                    }
                }
                KeyValues(title: "Local Storage", pairs: model.localStorage)
                KeyValues(title: "Session Storage", pairs: model.sessionStorage)
                // Destructive and set apart, so it is never hit by accident.
                Spacer(minLength: 24)
                Button("Clear Site Data…", role: .destructive) { model.perform(.clearSiteData) }.controlSize(.small)
            }
            .padding(12)
        }
    }

    private func flags(_ cookie: HTTPCookie) -> String {
        var parts = [cookie.domain]
        if cookie.isSecure { parts.append("Secure") }
        if cookie.isHTTPOnly { parts.append("HttpOnly") }
        if let date = cookie.expiresDate { parts.append(date.formatted(date: .abbreviated, time: .omitted)) } else { parts.append("Session") }
        return parts.joined(separator: " · ")
    }
}

private struct KeyValues: View {
    let title: String
    let pairs: [(String, String)]

    var body: some View {
        SectionTitle(title, count: pairs.count) { EmptyView() }
        if pairs.isEmpty { EmptyNote("Empty").frame(height: 24) }
        ForEach(pairs, id: \.0) { key, value in
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(key).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(width: 180, alignment: .leading)
                Text(value).font(.system(size: 12, design: .monospaced)).lineLimit(2).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: Page

private struct PageView: View {
    @Bindable var model: DevPanelModel
    @Bindable var tab: BrowserKit.Tab

    var body: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 14) {
                    SectionTitle("Vitals", count: nil) { EmptyView() }
                    VitalsGrid(vitals: tab.devTools.vitals)
                    SectionTitle("Tools", count: nil) { EmptyView() }
                    tools
                }
                .frame(width: 320, alignment: .leading)
                VStack(alignment: .leading, spacing: 8) {
                    if let response = tab.devTools.mainResponse {
                        SectionTitle("Response", count: nil) {
                            Text("\(response.statusCode) · \(response.mimeType ?? "unknown")")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(response.statusCode >= 400 ? Color(nsColor: Theme.fail) : Color(nsColor: Theme.textSecondary))
                        }
                        ForEach(response.headers, id: \.0) { name, value in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(name).font(.system(size: 12, weight: .medium, design: .monospaced)).frame(width: 200, alignment: .leading)
                                Text(value).font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    } else {
                        EmptyNote("Load a page to see its response")
                    }
                }
            }
            .padding(12)
        }
    }

    private var tools: some View {
        VStack(alignment: .leading, spacing: 10) {
            LabeledContent("Appearance") {
                Picker("", selection: $tab.colorSchemeOverride) {
                    Text("System").tag(String?.none)
                    Text("Light").tag(String?.some("light"))
                    Text("Dark").tag(String?.some("dark"))
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 180)
            }
            LabeledContent("Viewport") {
                Picker("", selection: $tab.viewportWidth) {
                    Text("Window").tag(CGFloat?.none)
                    Text("390").tag(CGFloat?.some(390))
                    Text("768").tag(CGFloat?.some(768))
                    Text("1024").tag(CGFloat?.some(1024))
                    Text("1440").tag(CGFloat?.some(1440))
                }
                .labelsHidden().frame(width: 180)
            }
            LabeledContent("JavaScript") {
                Toggle("", isOn: Binding(get: { tab.javaScriptEnabled }, set: { enabled in
                    tab.javaScriptEnabled = enabled
                    tab.reload()
                }))
                .toggleStyle(.switch).controlSize(.small).labelsHidden()
            }
            HStack(spacing: 6) {
                Button("View Source") { model.perform(.viewSource) }
                Button("Copy Screenshot") { model.perform(.copyScreenshot) }
                Button("Save PDF…") { model.perform(.savePDF) }
            }
            .controlSize(.small)
        }
        .font(.system(size: 12))
    }
}

private struct VitalsGrid: View {
    let vitals: Vitals

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
            row("TTFB", vitals.ttfb, good: 800, poor: 1800, format: ms)
            row("LCP", vitals.lcp, good: 2500, poor: 4000, format: ms)
            row("INP", vitals.inp, good: 200, poor: 500, format: ms)
            row("CLS", vitals.cls, good: 0.1, poor: 0.25) { String(format: "%.3f", $0) }
            row("Load", vitals.load, good: .infinity, poor: .infinity, format: ms)
        }
    }

    private func row(_ name: String, _ value: Double?, good: Double, poor: Double, format: (Double) -> String) -> some View {
        GridRow {
            Text(name).font(.system(size: 12, weight: .medium)).foregroundStyle(Color(nsColor: Theme.textSecondary))
            if let value {
                HStack(spacing: 6) {
                    Circle().fill(Color(nsColor: value <= good ? Theme.pass : value <= poor ? Theme.pending : Theme.fail))
                        .frame(width: 6, height: 6)
                        .opacity(good.isInfinite ? 0 : 1)
                    Text(format(value)).font(.system(size: 12, design: .monospaced))
                }
            } else {
                Text("–").foregroundStyle(Color(nsColor: Theme.textTertiary))
            }
        }
    }
}

// MARK: Shared pieces

private struct SectionTitle<Accessory: View>: View {
    let title: String
    let count: Int?
    @ViewBuilder var accessory: Accessory

    init(_ title: String, count: Int?, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.count = count
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(nsColor: Theme.textPrimary))
            if let count {
                Text("\(count)").font(.system(size: 11).monospacedDigit()).foregroundStyle(Color(nsColor: Theme.textTertiary))
            }
            Spacer()
            accessory
        }
    }
}

private struct FilterField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.roundedBorder)
            .controlSize(.small)
            .frame(maxWidth: 260)
    }
}

private struct EmptyNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).font(.system(size: 12)).foregroundStyle(Color(nsColor: Theme.textTertiary))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private func ms(_ value: Double) -> String {
    value >= 1000 ? String(format: "%.2f s", value / 1000) : "\(Int(value.rounded())) ms"
}

private func bytes(_ count: Int) -> String {
    ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
}
