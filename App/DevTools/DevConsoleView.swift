import BrowserKit
import SwiftUI

private struct ConsoleGroup: Identifiable {
    var id: Int { entry.id }
    let entry: ConsoleEntry
    var count: Int = 1
}

struct DevConsoleView: View {
    @Bindable var model: DevPanelModel
    let record: DevToolsRecord
    @State private var following = true
    @State private var unread = 0
    @FocusState private var inputFocused: Bool
    @FocusState private var listFocused: Bool

    private var groups: [ConsoleGroup] {
        var rows: [ConsoleGroup] = []
        for entry in record.console where model.levels.contains(entry.level) && (model.consoleFilter.isEmpty ||
            (entry.text + " " + entry.source).localizedCaseInsensitiveContains(model.consoleFilter)) {
            if let last = rows.last, last.entry.text == entry.text, last.entry.level == entry.level,
               last.entry.source == entry.source, last.entry.kind == entry.kind, last.entry.arguments == entry.arguments {
                rows[rows.count - 1].count += 1
            } else { rows.append(ConsoleGroup(entry: entry)) }
        }
        return rows
    }

    var body: some View {
        let rows = groups
        VStack(spacing: 0) {
            DevToolbar {
                DevSearch(text: $model.consoleFilter, prompt: "Search messages")
                    .onSubmit { listFocused = true }
                Menu {
                    ForEach(ConsoleEntry.Level.allCases, id: \.self) { level in
                        Toggle(level.rawValue.capitalized, isOn: Binding(get: { model.levels.contains(level) }, set: { on in
                            if on { model.levels.insert(level) } else { model.levels.remove(level) }
                        }))
                    }
                } label: { Text(model.levels.count == 5 ? "All levels" : "\(model.levels.count) levels") }
                Toggle("Preserve log", isOn: Binding(get: { record.preserveLog }, set: { record.preserveLog = $0 }))
                    .tint(Color(nsColor: Theme.controlSelectionTint))
                Button("Copy log") { devCopy(rows.map { "[\($0.entry.level.rawValue)] \($0.entry.text)" + ($0.count > 1 ? " (×\($0.count))" : "") }.joined(separator: "\n")) }.disabled(rows.isEmpty)
                Button("Clear") { record.clearConsole(); model.selectedConsole = nil; unread = 0 }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
            }
            DevRule()
            DevSplit(hasSelection: model.selectedConsole != nil, clearSelection: { model.selectedConsole = nil }) {
                ScrollViewReader { proxy in
                    List {
                        ForEach(rows) { group in
                            Button { model.selectedConsole = group.id } label: { row(group).contentShape(Rectangle()) }
                                .buttonStyle(.plain).id(group.id)
                                .accessibilityLabel("Inspect \(group.entry.level.rawValue): \(group.entry.text)")
                                .accessibilityAddTraits(model.selectedConsole == group.id ? .isSelected : [])
                                .listRowBackground(model.selectedConsole == group.id ? Color(nsColor: Theme.hoverFill) : .clear)
                                .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                                .listRowSeparatorTint(Color(nsColor: Theme.hairline))
                                .contextMenu { Button("Copy message") { devCopy(group.entry.text) } }
                        }
                    }
                    .listStyle(.plain).scrollContentBackground(.hidden)
                    .focusable().focused($listFocused)
                    .onKeyPress(.downArrow) { moveSelection(rows, step: 1); return .handled }
                    .onKeyPress(.upArrow) { moveSelection(rows, step: -1); return .handled }
                    .environment(\.defaultMinListRowHeight, 28)
                    .onScrollGeometryChange(for: Bool.self) { geo in
                        geo.contentOffset.y + geo.containerSize.height >= geo.contentSize.height - 8
                    } action: { _, atBottom in following = atBottom; if atBottom { unread = 0 } }
                    .onChange(of: record.console.last?.id) { _, _ in
                        guard record.console.last != nil else { unread = 0; following = true; return }
                        if following, let id = rows.last?.id { DispatchQueue.main.async { proxy.scrollTo(id, anchor: .bottom) } }
                        else { unread += 1 }
                    }
                    .overlay {
                        if rows.isEmpty { DevEmpty(title: record.console.isEmpty ? "Console is ready" : "No matching messages",
                            detail: record.console.isEmpty ? "Messages appear as the page runs. Evaluate JavaScript below. For the full Web Inspector, right-click the page › Inspect Element." : "Change your search or message levels.", symbol: "terminal") }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !following && unread > 0 {
                            Button("\(unread) new messages", systemImage: "arrow.down") {
                                following = true; unread = 0
                                if let id = rows.last?.id { proxy.scrollTo(id, anchor: .bottom) }
                            }.controlSize(.small).padding(10)
                        }
                    }
                }
            } detail: {
                if let group = rows.first(where: { $0.id == model.selectedConsole }) { detail(group) }
                else { DevEmpty(title: "Select a message", detail: "Read its full text, arguments and call stack.", symbol: "text.alignleft") }
            }
            DevRule()
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "chevron.right").foregroundStyle(Color(nsColor: Theme.accent))
                TextField("Evaluate JavaScript", text: $model.command, axis: .vertical)
                    .font(.system(size: 12, design: .monospaced)).textFieldStyle(.plain).lineLimit(1...4).focused($inputFocused)
                    .onSubmit { model.evaluate() }
                    .onKeyPress(.upArrow) { if !model.command.contains("\n") { model.moveHistory(-1); return .handled }; return .ignored }
                    .onKeyPress(.downArrow) { if !model.command.contains("\n") { model.moveHistory(1); return .handled }; return .ignored }
                Toggle("Await", isOn: $model.awaitExpression).help("Await an expression or promise. Turn off to run JavaScript statements.")
                    .font(.system(size: 11)).toggleStyle(.checkbox)
                    .tint(Color(nsColor: Theme.controlSelectionTint))
                Button { model.evaluate() } label: { Image(systemName: "play.fill") }.buttonStyle(.borderless)
                    .disabled(model.evaluating || model.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .help("Evaluate in the inspected page").accessibilityLabel("Evaluate JavaScript")
                if model.evaluating {
                    Button("Stop waiting") { model.stopWaitingForEvaluation() }.buttonStyle(.borderless).font(.system(size: 11))
                        .help("Allow another command; JavaScript already running in the page may continue.")
                }
            }.padding(.horizontal, 12).padding(.vertical, 8)
            DevRule()
            HStack {
                Text("\(rows.reduce(0) { $0 + $1.count }) messages")
                if record.errorCount > 0 { Text("\(record.errorCount) errors").foregroundStyle(Color(nsColor: Theme.fail)) }
                Spacer()
                Text(following ? "Following latest" : "Reading history")
            }.font(.system(size: 10)).foregroundStyle(devSecondary).padding(.horizontal, 12).frame(height: 24)
        }
    }

    private func moveSelection(_ rows: [ConsoleGroup], step: Int) {
        guard !rows.isEmpty else { return }
        let current = rows.firstIndex { $0.id == model.selectedConsole }
        let next = current.map { max(0, min(rows.count - 1, $0 + step)) } ?? (step > 0 ? 0 : rows.count - 1)
        model.selectedConsole = rows[next].id
    }

    private func row(_ group: ConsoleGroup) -> some View {
        let entry = group.entry
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(entry.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(devSecondary).frame(width: 65, alignment: .leading)
            Image(systemName: entry.kind == "command" ? "chevron.right" : entry.kind == "result" ? "arrow.turn.down.right" : glyph(entry.level))
                .font(.system(size: 10)).foregroundStyle(color(entry.level)).frame(width: 12)
            Text(entry.text.components(separatedBy: .newlines).first ?? entry.text).font(.system(size: 12, design: .monospaced))
                .foregroundStyle(devPrimary).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            if group.count > 1 { Text("×\(group.count)").font(.system(size: 10, design: .monospaced)).foregroundStyle(devSecondary) }
        }.help(entry.source)
    }

    private func detail(_ group: ConsoleGroup) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                DevHeading(title: group.entry.kind == "message" ? group.entry.level.rawValue.capitalized : group.entry.kind.capitalized,
                           action: "Copy message", copy: group.entry.text)
                DevCode(text: group.entry.text)
                if !group.entry.source.isEmpty { DevCode(text: group.entry.source) }
                if group.count > 1 { Text("Repeated \(group.count) times").font(.system(size: 11)).foregroundStyle(devSecondary) }
                ForEach(Array(group.entry.arguments.enumerated()), id: \.offset) { index, value in
                    DisclosureGroup("Argument \(index + 1)") { DevCode(text: devPretty(value)).padding(.top, 6) }.font(.system(size: 12))
                }
                if !group.entry.stack.isEmpty {
                    DevRule()
                    DevHeading(title: "Call stack", copy: group.entry.stack)
                    DevCode(text: group.entry.stack)
                }
            }.padding(16)
        }
    }
    private func color(_ level: ConsoleEntry.Level) -> Color {
        level == .error ? Color(nsColor: Theme.fail) : level == .warn ? Color(nsColor: Theme.pending) : devSecondary
    }
    private func glyph(_ level: ConsoleEntry.Level) -> String {
        switch level { case .error: "xmark.octagon.fill"; case .warn: "exclamationmark.triangle.fill"; case .info: "info.circle"; default: "chevron.right" }
    }
}
