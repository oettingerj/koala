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
        window.setFrameAutosaveName("KoalaSettings")
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
        // Grouped forms scroll and report no height of their own, so the window needs one.
        .frame(width: 560, height: 460)
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
                    Text("Koala is your default browser").foregroundStyle(.secondary)
                } else {
                    Button("Make Koala the Default Browser") {
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
    @State private var editor = GitHubService.shared.editor

    var body: some View {
        Form {
            Section {
                LabeledContent("Account") {
                    if github.isSignedIn {
                        Button("Sign Out") { github.signOut() }
                    } else {
                        Button("Sign In…") { NSApp.sendAction(#selector(BrowserWindowController.signInToGitHub(_:)), to: nil, from: nil) }
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
    @State private var removing: InstalledExtension?

    private var storeID: String? { ExtensionPackage.webStoreID(from: storeLink) }
    private var safariToAdd: [SafariExtensions.Found] {
        host.safariExtensions.filter { found in !host.installed.contains { $0.safariID == found.id } }
    }

    var body: some View {
        Form {
            Section {
                if host.installed.isEmpty {
                    VStack(spacing: 4) {
                        Image(systemName: "puzzlepiece.extension").font(.system(size: 22)).foregroundStyle(.tertiary)
                            .padding(.bottom, 4)
                        Text("No Extensions").font(.headline)
                        Text("Install one from the Chrome Web Store, or add one from a folder, ZIP, or CRX.")
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                } else {
                    ForEach(host.installed) { item in ExtensionRow(item: item) { removing = item } }
                }
            } footer: {
                Text("Koala runs Safari-compatible web extensions, including most Manifest V3 Chrome extensions.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !safariToAdd.isEmpty {
                Section {
                    ForEach(safariToAdd) { found in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(found.appName)
                                if found.usesNativeMessaging {
                                    Text("Needs to talk to its app, which Koala can’t do yet.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Button("Add") { Task { await host.addSafariExtension(found) } }
                                .disabled(found.usesNativeMessaging || host.isInstalling)
                        }
                    }
                } header: {
                    Text("Safari Extensions")
                } footer: {
                    Text("Extensions that come with apps you’ve installed. They load from the app and update with it.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Add") {
                HStack {
                    TextField("Chrome Web Store link", text: $storeLink, prompt: Text("Paste a Chrome Web Store link or extension ID"))
                        .labelsHidden()
                        .onSubmit(installFromStore)
                    Button(action: installFromStore) {
                        // The label keeps its width while the spinner shows.
                        Text("Install").opacity(host.isInstalling ? 0 : 1)
                            .overlay { if host.isInstalling { ProgressView().controlSize(.small) } }
                    }
                    .disabled(storeID == nil || host.isInstalling)
                }
                if !storeLink.isEmpty, storeID == nil {
                    Text("Paste the link to an extension’s page on chromewebstore.google.com, or its 32-letter ID.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = host.lastError {
                    Text(error).font(.caption).foregroundStyle(Color(nsColor: Theme.fail))
                }
                HStack {
                    Button("Browse Chrome Web Store") {
                        (NSApp.delegate as? AppDelegate)?.open(URL(string: "https://chromewebstore.google.com")!)
                    }
                    Spacer()
                    Button("Add from Folder, ZIP, or CRX…", action: chooseBundle)
                        .disabled(host.isInstalling)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { host.refreshSafariExtensions() }
        .confirmationDialog("Remove “\(removing?.name ?? "")”?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { item in
            Button("Remove", role: .destructive) { host.remove(item) }
        } message: { item in
            Text(item.safariID == nil ? "Koala deletes its files. You can add it again later." : "Its app stays installed. You can add it again later.")
        }
    }

    private func installFromStore() {
        guard storeID != nil, !host.isInstalling else { return }
        Task {
            if await host.installFromWebStore(storeLink) { storeLink = "" }
        }
    }

    private func chooseBundle() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.zip, .folder, .data]
        panel.prompt = "Add"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await host.install(from: url) }
        }
    }
}

private struct ExtensionRow: View {
    let item: InstalledExtension
    let onRemove: () -> Void
    @Bindable private var host = ExtensionsHost.shared

    var body: some View {
        // Icon, description, and options come from the loaded extension; disabled ones show the name only.
        let context = host.context(for: item)
        let failure = host.loadFailures[item.id]
        HStack(spacing: 10) {
            Group {
                if let icon = context?.webExtension.icon(for: CGSize(width: 24, height: 24)) {
                    Image(nsImage: icon).resizable()
                } else {
                    Image(systemName: "puzzlepiece.extension").font(.system(size: 16)).foregroundStyle(.tertiary)
                }
            }
            .frame(width: 24, height: 24)
            .opacity(item.isEnabled ? 1 : 0.5)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(item.name).foregroundStyle(item.isEnabled ? .primary : .secondary)
                    Text(item.version).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                if let failure {
                    Text("Didn’t load: \(failure)").font(.caption).foregroundStyle(Color(nsColor: Theme.fail)).lineLimit(2)
                } else if let description = context?.webExtension.displayDescription, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer()
            Toggle("Enabled", isOn: Binding(get: { item.isEnabled }, set: { host.setEnabled($0, for: item) }))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            Menu {
                if context != nil {
                    Button(item.isPinned ? "Unpin from Toolbar" : "Pin to Toolbar") { host.setPinned(!item.isPinned, for: item.id) }
                }
                if let options = context?.optionsPageURL {
                    Button("Options…") { (NSApp.delegate as? AppDelegate)?.open(options) }
                }
                if context != nil { Divider() }
                Button("Remove…", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button).buttonStyle(.borderless).menuIndicator(.hidden).fixedSize()
            .help("More")
        }
    }
}
