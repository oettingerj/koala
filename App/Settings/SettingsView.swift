import AppKit
import BrowserKit
import SwiftUI

/// Settings that persist in user defaults and feed AppServices.
@MainActor
enum Preferences {
    static let searchEngines: [(name: String, template: String)] = [
        ("Google", "https://www.google.com/search?q=%s"),
        ("DuckDuckGo", "https://duckduckgo.com/?q=%s"),
        ("Kagi", "https://kagi.com/search?q=%s"),
        ("Bing", "https://www.bing.com/search?q=%s"),
    ]

    static var searchTemplate: String {
        get { UserDefaults.standard.string(forKey: "SearchTemplate") ?? AddressInput.defaultSearchTemplate }
        set { UserDefaults.standard.set(newValue, forKey: "SearchTemplate"); apply() }
    }

    static var webSuggestions: Bool {
        get { UserDefaults.standard.object(forKey: "WebSuggestions") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "WebSuggestions"); apply() }
    }

    static var keywordSearches: [KeywordSearch] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "KeywordSearches"),
                  let searches = try? JSONDecoder().decode([KeywordSearch].self, from: data) else { return KeywordSearch.defaults }
            return searches
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "KeywordSearches")
            apply()
        }
    }

    static func apply() {
        let engine = AppServices.shared.suggestions
        engine.searchTemplate = searchTemplate
        engine.webSuggestionsEnabled = webSuggestions
        engine.keywordSearches = keywordSearches
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Settings"
        window.styleMask = [.titled, .closable]
        window.setFrameAutosaveName("NanoSettings")
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            GitHubSettings().tabItem { Label("GitHub", systemImage: "arrow.triangle.pull") }
            KeywordSettings().tabItem { Label("Search Keywords", systemImage: "magnifyingglass") }
            ExtensionSettings().tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }
        }
        .frame(width: 560)
        .tint(Color(nsColor: Theme.accent))
    }
}

private struct GeneralSettings: View {
    @State private var template = Preferences.searchTemplate
    @State private var suggestions = Preferences.webSuggestions
    @State private var isDefault = false

    var body: some View {
        Form {
            Picker("Search engine", selection: $template) {
                ForEach(Preferences.searchEngines, id: \.template) { engine in Text(engine.name).tag(engine.template) }
            }
            .onChange(of: template) { _, value in Preferences.searchTemplate = value }
            Toggle("Show search suggestions while typing", isOn: $suggestions)
                .onChange(of: suggestions) { _, value in Preferences.webSuggestions = value }
            Text("Suggestions send what you type in the address field and command bar to your search engine.")
                .font(.caption).foregroundStyle(.secondary)
            LabeledContent("Default browser") {
                if isDefault {
                    Text("Nano is your default browser").foregroundStyle(.secondary)
                } else {
                    Button("Make Nano the Default Browser") {
                        Task {
                            try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http")
                            checkDefault()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: checkDefault)
    }

    private func checkDefault() {
        let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        isDefault = handler?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }
}

private struct GitHubSettings: View {
    @Bindable private var github = GitHubService.shared
    @State private var clientID = GitHubService.shared.clientID
    @State private var editor = GitHubService.shared.editor

    var body: some View {
        Form {
            Section {
                TextField("OAuth client ID", text: $clientID, prompt: Text("Ov23li…"))
                    .font(.system(.body, design: .monospaced))
                    .onChange(of: clientID) { _, value in github.clientID = value }
                Text("Register an OAuth app on GitHub with Device Flow enabled, then paste its client ID. Nano never needs the client secret.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Register an OAuth App on GitHub…") {
                    NSWorkspace.shared.open(URL(string: "https://github.com/settings/applications/new")!)
                }
                LabeledContent("Account") {
                    if github.isSignedIn {
                        Button("Sign Out") { github.signOut() }
                    } else {
                        Button("Sign In…") { NSApp.sendAction(#selector(BrowserWindowController.signInToGitHub(_:)), to: nil, from: nil) }
                            .disabled(clientID.isEmpty)
                    }
                }
                if let error = github.lastError {
                    Text(error).font(.caption).foregroundStyle(Color(nsColor: Theme.fail))
                }
            }
            Section("Open in Editor") {
                LabeledContent("Code folder") {
                    HStack {
                        Text(github.codeRoot?.path ?? "Not set").foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.canChooseDirectories = true
                            panel.canChooseFiles = false
                            panel.prompt = "Use Folder"
                            if panel.runModal() == .OK, let url = panel.url { github.setCodeRoot(url) }
                        }
                    }
                }
                if github.codeRoot != nil {
                    LabeledContent("Clones found") { Text("\(github.clones.clones.count)").monospacedDigit() }
                }
                Picker("Editor", selection: $editor) {
                    ForEach(CodeEditor.allCases) { editor in Text(editor.name).tag(editor) }
                }
                .onChange(of: editor) { _, value in github.editor = value }
            }
        }
        .formStyle(.grouped)
    }
}

private struct KeywordSettings: View {
    @State private var searches = Preferences.keywordSearches
    @State private var selection: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type a keyword and a space in the address field or command bar to search that site. Use %s where the query goes.")
                .font(.caption).foregroundStyle(.secondary)
            Table($searches, selection: $selection) {
                TableColumn("Keyword") { $search in TextField("", text: $search.keyword).font(.system(.body, design: .monospaced)) }
                    .width(80)
                TableColumn("Name") { $search in TextField("", text: $search.name) }.width(130)
                TableColumn("URL") { $search in TextField("", text: $search.template).font(.system(.caption, design: .monospaced)) }
            }
            .frame(height: 260)
            HStack {
                Button { searches.append(KeywordSearch(keyword: "new", name: "New Search", template: "https://example.com/?q=%s")) } label: {
                    Image(systemName: "plus")
                }
                Button { searches.removeAll { $0.id == selection } } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                Spacer()
                Button("Restore Defaults") { searches = KeywordSearch.defaults }
            }
        }
        .padding(20)
        .onChange(of: searches) { _, value in
            // Keep only well-formed entries: a single-word keyword and a template with %s.
            Preferences.keywordSearches = value.filter { !$0.keyword.isEmpty && !$0.keyword.contains(" ") && $0.template.contains("%s") }
        }
    }
}

private struct ExtensionSettings: View {
    @Bindable private var host = ExtensionsHost.shared
    @State private var storeLink = ""
    @State private var isInstalling = false

    var body: some View {
        Form {
            Section {
                if host.installed.isEmpty {
                    Text("No extensions yet. Nano runs Safari-compatible web extensions, including most Manifest V3 Chrome extensions.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                ForEach(host.installed) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text(item.version).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("Enabled", isOn: Binding(get: { item.isEnabled }, set: { host.setEnabled($0, for: item) }))
                            .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        Button("Remove", role: .destructive) { host.remove(item) }.controlSize(.small)
                    }
                }
            }
            Section("Add") {
                HStack {
                    TextField("Chrome Web Store link or extension ID", text: $storeLink)
                    Button("Install") {
                        isInstalling = true
                        Task {
                            await host.installFromWebStore(storeLink)
                            isInstalling = false
                            if host.lastError == nil { storeLink = "" }
                        }
                    }
                    .disabled(storeLink.isEmpty || isInstalling)
                }
                Button("Add from Folder, ZIP, or CRX…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = true
                    panel.allowedContentTypes = [.zip, .folder, .data]
                    panel.prompt = "Add"
                    if panel.runModal() == .OK, let url = panel.url {
                        Task { await host.install(from: url) }
                    }
                }
                if isInstalling { ProgressView().controlSize(.small) }
                if let error = host.lastError {
                    Text(error).font(.caption).foregroundStyle(Color(nsColor: Theme.fail))
                }
            }
        }
        .formStyle(.grouped)
    }
}
