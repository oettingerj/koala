import AppKit
import BrowserKit
import SwiftUI

/// The fixed rows of each section. Lists (keywords, extensions) build their entries from live data.
@MainActor
enum SettingEntries {
    static let searchEngine = SettingEntry(
        id: "search-engine", section: .general, title: "Search engine",
        detail: "Where searches from the address field and command bar go.",
        terms: Preferences.searchEngines.map(\.name) + ["query"])
    static let suggestions = SettingEntry(
        id: "suggestions", section: .general, title: "Suggestions while typing",
        detail: "Sends what you type in the address field and command bar to your search engine.",
        terms: ["autocomplete", "privacy", "web"])
    static let defaultBrowser = SettingEntry(
        id: "default-browser", section: .general, title: "Default browser",
        terms: ["links", "open", "system"])
    static let startup = SettingEntry(
        id: "startup", section: .general, title: "At startup",
        detail: "Recently closed tabs and windows stay available either way.",
        terms: ["launch", "restore", "session", "windows", "tabs", "open"])
    static let tabSleep = SettingEntry(
        id: "tab-sleep", section: .general, title: "Sleep background tabs",
        detail: "Frees a tab’s memory after it sits unseen this long. It reloads when you return. Tabs that are pinned, playing sound, or holding typed text stay awake.",
        terms: ["memory", "performance", "idle", "suspend", "discard", "battery"])
    static let downloads = SettingEntry(
        id: "download-folder", section: .general, title: "Download to",
        terms: ["downloads", "folder", "save", "files", "location"])
    static let general = [searchEngine, suggestions, defaultBrowser, startup, tabSleep, downloads]

    static let githubAccount = SettingEntry(
        id: "github-account", section: .github, title: "Account",
        terms: ["sign in", "sign out", "login", "token", "review queue"])
    static let codeFolder = SettingEntry(
        id: "code-folder", section: .github, title: "Code folder",
        detail: "Open in Editor looks here for local clones of the repository you’re viewing.",
        terms: ["clones", "repositories", "path", "directory"])
    static let editor = SettingEntry(
        id: "editor", section: .github, title: "Editor",
        detail: "Open in Editor (⌥⌘E) opens the file at the line you’re viewing.",
        terms: CodeEditor.allCases.map(\.name) + ["ide", "open in editor"])
    static let dockBadge = SettingEntry(
        id: "dock-badge", section: .github, title: "Show review count on Dock icon",
        detail: "Pull requests waiting on your review.",
        terms: ["badge", "dock", "notifications", "review queue", "count"])
    static let github = [githubAccount, codeFolder, editor, dockBadge]

    static let importData = SettingEntry(
        id: "import", section: .data, title: "Import",
        detail: "Bookmarks and history from a Chrome or Brave profile. For Arc or Safari, choose their bookmarks file.",
        terms: ["chrome", "brave", "arc", "safari", "bookmarks", "history"])
    static let bookmarksBar = SettingEntry(
        id: "bookmarks-bar", section: .data, title: "Show bookmarks bar",
        detail: "A row of bookmarks under the toolbar. ⇧⌘B shows or hides it.",
        terms: ["bookmarks", "toolbar"])
    static let clearHistory = SettingEntry(
        id: "clear-history", section: .data, title: "Clear history",
        detail: "Removes visited pages from history and address suggestions. Bookmarks and open tabs stay.",
        terms: ["delete", "privacy", "visited"])
    static let data = [importData, bookmarksBar, clearHistory]
}

// MARK: General

struct GeneralSettings: View {
    @State private var template = Preferences.searchTemplate
    @State private var restoresSession = Preferences.restoresSession
    @State private var sleepMinutes = Preferences.tabSleepMinutes
    @State private var downloadFolder = Preferences.downloadFolder
    @State private var suggestions = Preferences.webSuggestions
    @State private var isDefault = false

    private var engine: (name: String, template: String, suggestions: String?)? {
        Preferences.searchEngines.first { $0.template == template }
    }

    private var offersSuggestions: Bool { engine?.suggestions != nil }

    private var suggestionsDetail: String {
        guard offersSuggestions, let engine else {
            return "Koala doesn’t get suggestions from \(engine?.name ?? "this search engine"), so nothing you type is sent until you search."
        }
        return "Sends what you type in the address field and command bar to \(engine.name)."
    }

    var body: some View {
        VStack(spacing: 0) {
            SettingRow(SettingEntries.searchEngine) {
                Picker("Search engine", selection: $template) {
                    ForEach(Preferences.searchEngines, id: \.template) { engine in Text(engine.name).tag(engine.template) }
                }
                .labelsHidden()
                .onChange(of: template) { _, value in Preferences.searchTemplate = value }
            }
            SettingRow(SettingEntries.suggestions, detail: { SettingDetail(text: suggestionsDetail) }) {
                Toggle("Suggestions while typing", isOn: offersSuggestions ? $suggestions : .constant(false))
                    .settingsSwitch()
                    .disabled(!offersSuggestions)
                    .onChange(of: suggestions) { _, value in Preferences.webSuggestions = value }
            }
            SettingRow(SettingEntries.defaultBrowser) {
                if isDefault {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(nsColor: Theme.pass)).accessibilityHidden(true)
                        Text("Koala is your default browser").foregroundStyle(settingsSecondary)
                    }
                    .font(.system(size: 12))
                } else {
                    Button("Make Koala the Default") {
                        Task {
                            try? await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: "http")
                            checkDefault()
                        }
                    }
                }
            }
            SettingRow(SettingEntries.startup) {
                Picker("At startup", selection: $restoresSession) {
                    Text("Restore windows and tabs").tag(true)
                    Text("Open a new window").tag(false)
                }
                .labelsHidden()
                .onChange(of: restoresSession) { _, value in Preferences.restoresSession = value }
            }
            SettingRow(SettingEntries.tabSleep) {
                Picker("Sleep background tabs", selection: $sleepMinutes) {
                    Text("After 15 minutes").tag(15)
                    Text("After 30 minutes").tag(30)
                    Text("After 1 hour").tag(60)
                    Text("After 2 hours").tag(120)
                    Text("Never").tag(0)
                }
                .labelsHidden()
                .onChange(of: sleepMinutes) { _, value in Preferences.tabSleepMinutes = value }
            }
            SettingRow(SettingEntries.downloads) {
                Text((downloadFolder.path as NSString).abbreviatingWithTildeInPath)
                    .font(.mono(size: 11)).foregroundStyle(settingsSecondary)
                    .lineLimit(1).truncationMode(.middle).textSelection(.enabled).help(downloadFolder.path)
            } control: {
                HStack(spacing: 8) {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([downloadFolder]) }
                    Button("Choose…", action: chooseDownloadFolder)
                }
            }
        }
        .onAppear(perform: checkDefault)
        // The default can change in System Settings while the tab stays open.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in checkDefault() }
    }

    private func chooseDownloadFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.directoryURL = downloadFolder
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Preferences.downloadFolder = url
        downloadFolder = url
    }

    private func checkDefault() {
        let handler = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
        isDefault = handler?.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
    }
}

// MARK: GitHub

struct GitHubSettings: View {
    @Bindable private var github = GitHubService.shared
    @State private var editor = GitHubService.shared.editor

    var body: some View {
        VStack(spacing: 0) {
            SettingsRowFrame(SettingEntries.githubAccount) { account }
            SettingRow(SettingEntries.codeFolder) {
                if let root = github.codeRoot {
                    HStack(spacing: 6) {
                        Text((root.path as NSString).abbreviatingWithTildeInPath)
                            .font(.mono(size: 11)).foregroundStyle(settingsSecondary)
                            .lineLimit(1).truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(root.path)
                        Text(github.clones.clones.count == 1 ? "1 clone" : "\(github.clones.clones.count) clones")
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(settingsTertiary)
                            .fixedSize()
                    }
                } else {
                    SettingDetail(text: SettingEntries.codeFolder.detail)
                }
            } control: {
                HStack(spacing: 8) {
                    if let root = github.codeRoot {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([root]) }
                    }
                    Button("Choose…", action: chooseCodeFolder)
                }
            }
            SettingRow(SettingEntries.editor) {
                HStack(spacing: 8) {
                    if let icon = Self.icon(of: editor) {
                        Image(nsImage: icon).resizable().frame(width: 18, height: 18).accessibilityHidden(true)
                    } else {
                        Text("Not installed").font(.system(size: 11)).foregroundStyle(settingsTertiary)
                    }
                    Picker("Editor", selection: $editor) {
                        ForEach(CodeEditor.allCases) { editor in Text(editor.name).tag(editor) }
                    }
                    .labelsHidden()
                    .onChange(of: editor) { _, value in github.editor = value }
                }
            }
            SettingRow(SettingEntries.dockBadge) {
                Toggle("Show review count on Dock icon", isOn: $github.showsDockBadge).settingsSwitch()
            }
        }
    }

    private var account: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                avatar
                VStack(alignment: .leading, spacing: 3) {
                    if github.isSignedIn {
                        SettingTitle(github.account.map { $0.name ?? $0.login } ?? "Signed in to GitHub", weight: .semibold)
                        HStack(spacing: 8) {
                            if let login = github.account?.login {
                                Text("@\(login)").font(.mono(size: 11)).foregroundStyle(settingsSecondary)
                                    .textSelection(.enabled)
                            }
                            Text(queueSummary).font(.system(size: 11).monospacedDigit()).foregroundStyle(settingsTertiary)
                        }
                    } else {
                        SettingTitle("Not signed in", weight: .semibold)
                        SettingDetail(text: "Sign in to see PR and CI status in tabs, and to fill your review queue.")
                    }
                }
                Spacer(minLength: 16)
                if github.isSignedIn {
                    Button("Sign Out") { github.signOut() }
                } else {
                    Button("Sign In…") {
                        NSApp.sendAction(#selector(BrowserWindowController.signInToGitHub(_:)), to: nil, from: nil)
                    }
                    .buttonStyle(SettingsPrimaryButtonStyle())
                }
            }
            if let error = github.lastError {
                Text(error).font(.system(size: 11)).foregroundStyle(settingsFail).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("GitHub account")
    }

    private var avatar: some View {
        Group {
            if let url = github.account?.avatarURL {
                AsyncImage(url: url) { image in
                    image.resizable().interpolation(.high)
                } placeholder: {
                    Color(nsColor: Theme.fieldFill)
                }
            } else {
                Image(systemName: "person.crop.circle")
                    .font(.system(size: 30, weight: .light)).foregroundStyle(settingsTertiary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(Color(nsColor: Theme.hairline), lineWidth: 1) }
        .accessibilityHidden(true)
    }

    private var queueSummary: String {
        switch github.queue.count {
        case 0: "Review queue is clear"
        case 1: "1 in your review queue"
        case let count: "\(count) in your review queue"
        }
    }

    private func chooseCodeFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use Folder"
        panel.directoryURL = github.codeRoot
        if panel.runModal() == .OK, let url = panel.url { github.setCodeRoot(url) }
    }

    private static func icon(of editor: CodeEditor) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: editor.bundleIdentifier).map { NSWorkspace.shared.icon(forFile: $0.path) }
    }
}

// MARK: Browsing data

struct BrowsingDataSettings: View {
    /// Read here so ⇧⌘B in any window keeps the switch current.
    @AppStorage("ShowBookmarksBar") private var showsBookmarksBar = false

    var body: some View {
        VStack(spacing: 0) {
            SettingRow(SettingEntries.importData) {
                HStack(spacing: 8) {
                    Button("Chrome…") { send(#selector(BrowserWindowController.importFromChrome(_:))) }
                    Button("Brave…") { send(#selector(BrowserWindowController.importFromBrave(_:))) }
                    Button("Bookmarks File…") { send(#selector(BrowserWindowController.importBookmarksFile(_:))) }
                }
            }
            SettingRow(SettingEntries.bookmarksBar) {
                Toggle("Show bookmarks bar", isOn: Binding(get: { showsBookmarksBar }, set: BrowserWindowController.setBookmarksBar))
                    .settingsSwitch()
            }
            SettingRow(SettingEntries.clearHistory) {
                Button("Clear History…") { send(#selector(AppDelegate.clearHistory(_:))) }
            }
        }
    }

    /// The page lives in a browser window, so the window and app delegate handle these like menu items.
    private func send(_ action: Selector) {
        NSApp.sendAction(action, to: nil, from: nil)
    }
}
