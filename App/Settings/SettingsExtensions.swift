import AppKit
import BrowserKit
import SwiftUI
import WebKit

struct ExtensionSettings: View {
    @Bindable private var host = ExtensionsHost.shared
    @Environment(\.settingsFilter) private var filter
    @State private var storeLink = ""
    @State private var removing: InstalledExtension?

    static let addEntry = SettingEntry(
        id: "add-extension", section: .extensions, title: "Add an extension",
        terms: ["install", "chrome web store", "crx", "zip", "folder"])
    private static let emptyEntry = SettingEntry(id: "no-extensions", section: .extensions, title: "No extensions")

    @MainActor static func entry(for item: InstalledExtension) -> SettingEntry {
        let description = ExtensionsHost.shared.context(for: item)?.webExtension.displayDescription
        return SettingEntry(id: item.id, section: .extensions, title: item.name, detail: description,
                            terms: [item.version, item.isEnabled ? "enabled" : "disabled",
                                    item.isPinned ? "pinned toolbar" : "pin toolbar", "options", "remove"])
    }

    @MainActor static func entry(for found: SafariExtensions.Found) -> SettingEntry {
        SettingEntry(id: "safari-\(found.id)", section: .extensions, title: found.appName,
                     detail: "Comes with an app you’ve installed. It loads from the app and updates with it.",
                     terms: ["safari", "app"])
    }

    @MainActor static func entries() -> [SettingEntry] {
        let host = ExtensionsHost.shared
        return host.installed.map(entry(for:)) + safariToAdd(host).map(entry(for:)) + [addEntry]
    }

    @MainActor private static func safariToAdd(_ host: ExtensionsHost) -> [SafariExtensions.Found] {
        host.safariExtensions.filter { found in !host.installed.contains { $0.safariID == found.id } }
    }

    /// The icon of the app that ships the extension: the app bundle enclosing the `.appex`.
    private static func appIcon(for found: SafariExtensions.Found) -> NSImage {
        var url = found.url
        while url.pathComponents.count > 1, url.pathExtension != "app" { url.deleteLastPathComponent() }
        return NSWorkspace.shared.icon(forFile: url.pathExtension == "app" ? url.path : found.url.path)
    }

    private var storeID: String? { ExtensionPackage.webStoreID(from: storeLink) }

    var body: some View {
        VStack(spacing: 0) {
            if host.installed.isEmpty {
                if !filter.isActive { SettingsRowFrame(Self.emptyEntry) { empty } }
            } else {
                ForEach(host.installed) { item in ExtensionRow(item: item) { removing = item } }
            }
            ForEach(Self.safariToAdd(host)) { found in
                SettingsRowFrame(Self.entry(for: found)) {
                    HStack(spacing: 12) {
                        Image(nsImage: Self.appIcon(for: found)).resizable().frame(width: 32, height: 32).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            SettingTitle(found.appName)
                            SettingDetail(text: found.usesNativeMessaging
                                          ? "Needs to talk to its app, which Koala can’t do yet." : Self.entry(for: found).detail)
                        }
                        Spacer(minLength: 16)
                        Button("Add") { Task { await host.addSafariExtension(found) } }
                            .disabled(found.usesNativeMessaging || host.isInstalling)
                    }
                }
            }
            SettingsRowFrame(Self.addEntry) { add }
        }
        .onAppear { host.refreshSafariExtensions() }
        .confirmationDialog("Remove “\(removing?.name ?? "")”?",
                            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            presenting: removing) { item in
            Button("Remove", role: .destructive) { host.remove(item) }
        } message: { item in
            Text(item.safariID == nil ? "Koala deletes its files. You can add it again later." : "Its app stays installed. You can add it again later.")
        }
    }

    private var empty: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension").font(.system(size: 20)).foregroundStyle(settingsTertiary)
                .frame(width: 32, height: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                SettingTitle("No extensions yet", weight: .semibold)
                SettingDetail(text: "Paste a Chrome Web Store link below, or add one from a folder, ZIP, or CRX.")
            }
        }
    }

    private var add: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingTitle(Self.addEntry.title)
            HStack(spacing: 8) {
                TextField("Chrome Web Store link", text: $storeLink, prompt: Text("Paste a Chrome Web Store link or extension ID"))
                    .labelsHidden().textFieldStyle(.roundedBorder)
                    .onSubmit(installFromStore)
                Button(action: installFromStore) {
                    // The label keeps its width while the spinner shows.
                    Text("Install").opacity(host.isInstalling ? 0 : 1)
                        .overlay { if host.isInstalling { ProgressView().controlSize(.small) } }
                }
                .disabled(storeID == nil || host.isInstalling)
            }
            if !storeLink.isEmpty, storeID == nil {
                SettingDetail(text: "Paste the link to an extension’s page on chromewebstore.google.com, or its 32-letter ID.")
            }
            if let error = host.lastError {
                Text(error).font(.system(size: 11)).foregroundStyle(settingsFail).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Browse Chrome Web Store") {
                    (NSApp.delegate as? AppDelegate)?.open(URL(string: "https://chromewebstore.google.com")!)
                }
                .buttonStyle(.borderless).foregroundStyle(Color(nsColor: Theme.accentText))
                Spacer()
                Button("Add from Folder, ZIP, or CRX…", action: chooseBundle)
                    .disabled(host.isInstalling)
            }
            .font(.system(size: 12))
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
    @Environment(\.settingsFilter) private var filter
    /// Read from the extension's files, so it loads once the extension does rather than on every render.
    @State private var access: ExtensionAccess?

    var body: some View {
        // Icon, description, and options come from the loaded extension; disabled ones show the name only.
        let context = host.context(for: item)
        let failure = host.loadFailures[item.id]
        SettingsRowFrame(ExtensionSettings.entry(for: item)) {
            HStack(alignment: .top, spacing: 12) {
                icon(context).opacity(item.isEnabled ? 1 : 0.6)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        SettingTitle(item.name, weight: .semibold)
                        Text(filter.highlight(item.version, size: 11, design: .monospaced))
                            .font(.system(size: 11, design: .monospaced)).foregroundStyle(settingsTertiary)
                    }
                    if let failure {
                        Text("Didn’t load: \(failure)").font(.system(size: 12)).foregroundStyle(settingsFail).lineLimit(2)
                    } else if let description = context?.webExtension.displayDescription, !description.isEmpty {
                        Text(filter.highlight(description, size: 12)).font(.system(size: 12)).foregroundStyle(settingsSecondary).lineLimit(2)
                    }
                    if let summary = access.flatMap(Self.summary) {
                        Text(summary).font(.system(size: 11)).foregroundStyle(settingsTertiary).lineLimit(2)
                    }
                    actions(context)
                }
                // A disabled extension dims its content; the switch that turns it back on stays at full strength.
                .opacity(item.isEnabled ? 1 : 0.6)
                Spacer(minLength: 16)
                Toggle("Enabled", isOn: Binding(get: { item.isEnabled }, set: { host.setEnabled($0, for: item) }))
                    .settingsSwitch()
                    .accessibilityLabel("Enable \(item.name)")
            }
        }
        .task(id: context.map(ObjectIdentifier.init)) { access = host.access(for: item) }
    }

    private func icon(_ context: WKWebExtensionContext?) -> some View {
        Group {
            if let image = context?.webExtension.icon(for: CGSize(width: 32, height: 32)) {
                Image(nsImage: image).resizable()
            } else {
                Image(systemName: "puzzlepiece.extension").font(.system(size: 20)).foregroundStyle(settingsTertiary)
            }
        }
        .frame(width: 32, height: 32)
        .accessibilityHidden(true)
    }

    private func actions(_ context: WKWebExtensionContext?) -> some View {
        HStack(spacing: 14) {
            if context != nil {
                Button { host.setPinned(!item.isPinned, for: item.id) } label: {
                    Label(item.isPinned ? "Pinned to Toolbar" : "Pin to Toolbar", systemImage: item.isPinned ? "pin.fill" : "pin")
                }
                .help(item.isPinned ? "Unpin from the toolbar" : "Show in the toolbar")
            }
            if let options = context?.optionsPageURL {
                Button("Options…") { (NSApp.delegate as? AppDelegate)?.open(options) }
            }
            Button("Remove…", action: onRemove).foregroundStyle(settingsTertiary)
        }
        .font(.system(size: 11))
        .buttonStyle(.borderless)
        .tint(Color(nsColor: Theme.accentText))
        .padding(.top, 2)
    }

    /// "Every website · storage, tabs", or the first few sites it asks for.
    private static func summary(_ access: ExtensionAccess) -> String? {
        var parts: [String] = []
        if access.allSites {
            parts.append("Can read and change every website")
        } else if !access.sites.isEmpty {
            parts.append("Sites: " + access.sites.prefix(3).joined(separator: ", ") + (access.sites.count > 3 ? " +\(access.sites.count - 3)" : ""))
        }
        if !access.permissions.isEmpty { parts.append(access.permissions.joined(separator: ", ")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
