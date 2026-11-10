import AppKit
import BrowserKit
import SwiftUI
import WebKit

extension SettingEntries {
    static let mediaPermissions = SettingEntry(
        id: "site-media", section: .sites, title: "Camera, microphone, and location",
        detail: "Sites you allowed or blocked. A site you remove asks again next time.",
        terms: ["permissions", "camera", "microphone", "video", "audio", "location", "geolocation", "allow", "block"])
    static var siteZoom: SettingEntry { SettingEntry(
        id: "site-zoom", section: .sites, title: "Zoom",
        detail: "Sites you zoomed in or out." + (MenuShortcuts.text(for: #selector(BrowserWindowController.actualSize(_:)))
            .map { " \($0) on a page resets it too." } ?? ""),
        terms: ["zoom", "scale", "size", "text"]) }
    static let certificates = SettingEntry(
        id: "site-certificates", section: .sites, title: "Certificate exceptions",
        detail: "Servers you visited despite an untrusted certificate. Koala forgets them when it quits.",
        terms: ["certificate", "tls", "ssl", "https", "trust", "security", "self-signed"])
    static let websiteData = SettingEntry(
        id: "site-data", section: .sites, title: "Website data",
        detail: "Cookies, storage, and caches sites keep. Removing a site’s data signs you out of it.",
        terms: ["cookies", "storage", "cache", "local storage", "privacy", "sign out"])
    static var sites: [SettingEntry] { [mediaPermissions, siteZoom, certificates, websiteData] }
}

// MARK: Sites

struct SitesSettings: View {
    @Bindable private var permissions = SitePermissions.shared
    @Bindable private var zoom = SiteZoom.shared
    @Bindable private var trust = TrustExceptions.shared
    @State private var records: [WKWebsiteDataRecord]?

    var body: some View {
        VStack(spacing: 0) {
            SiteList(entry: SettingEntries.mediaPermissions, empty: "No sites have asked yet.",
                     items: permissions.decisions.keys.sorted()) { key in
                let site = SitePermissions.describe(key)
                SiteItem(title: site.origin, detail: site.device) {
                    Picker(site.device, selection: Binding(get: { permissions.decisions[key] ?? false },
                                                           set: { permissions.set($0, key: key) })) {
                        Text("Allow").tag(true)
                        Text("Block").tag(false)
                    }
                    .labelsHidden().fixedSize()
                    removeButton(site.origin) { permissions.remove(key) }
                }
            }
            SiteList(entry: SettingEntries.siteZoom, empty: "Every site is at actual size.",
                     items: zoom.levels.keys.sorted()) { host in
                SiteItem(title: host, detail: "\(Int(((zoom.levels[host] ?? 1) * 100).rounded()))%") {
                    Button("Reset") { zoom.reset(host) }
                }
            }
            SiteList(entry: SettingEntries.certificates, empty: "None this session.", items: trust.keys.sorted()) { key in
                SiteItem(title: key, detail: nil) { removeButton(key) { trust.remove(key) } }
            }
            SiteList(entry: SettingEntries.websiteData, empty: records == nil ? "Loading…" : "No sites have stored data.",
                     items: (records ?? []).map(\.displayName)) { name in
                SiteItem(title: name, detail: nil) {
                    removeButton(name) { remove(records?.filter { $0.displayName == name } ?? []) }
                }
            } trailing: {
                Button("Remove All…", action: confirmRemoveAll).disabled(records?.isEmpty ?? true)
            }
        }
        .task { await loadRecords() }
    }

    private func removeButton(_ name: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle").font(.system(size: 13)).foregroundStyle(settingsTertiary)
        }
        .buttonStyle(.plain).help("Remove").accessibilityLabel("Remove \(name)")
    }

    private func loadRecords() async {
        let store = WKWebsiteDataStore.default()
        records = await store.dataRecords(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes())
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private func remove(_ matching: [WKWebsiteDataRecord]) {
        Task {
            await WKWebsiteDataStore.default().removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), for: matching)
            await loadRecords()
        }
    }

    private func confirmRemoveAll() {
        let alert = NSAlert()
        alert.messageText = "Remove all website data?"
        alert.informativeText = "Removes cookies, storage, and caches for every site. You will be signed out of them."
        alert.addButton(withTitle: "Remove All")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        remove(records ?? [])
    }
}

/// A settings row whose body is a list of sites, or a quiet line when there are none.
private struct SiteList<Item: Hashable, Row: View, Trailing: View>: View {
    let entry: SettingEntry
    let empty: String
    let items: [Item]
    @ViewBuilder var row: (Item) -> Row
    @ViewBuilder var trailing: Trailing

    init(entry: SettingEntry, empty: String, items: [Item], @ViewBuilder row: @escaping (Item) -> Row,
         @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.entry = entry
        self.empty = empty
        self.items = items
        self.row = row
        self.trailing = trailing()
    }

    var body: some View {
        SettingsRowFrame(entry) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        SettingTitle(entry.title)
                        SettingDetail(text: entry.detail)
                    }
                    Spacer(minLength: 16)
                    trailing.fixedSize()
                }
                if items.isEmpty {
                    Text(empty).font(.system(size: 12)).foregroundStyle(settingsTertiary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(items, id: \.self) { item in row(item) }
                    }
                    .background(RoundedRectangle(cornerRadius: Theme.controlRadius).fill(Color(nsColor: Theme.fieldFill)))
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}

private struct SiteItem<Controls: View>: View {
    let title: String
    let detail: String?
    @ViewBuilder var controls: Controls

    var body: some View {
        HStack(spacing: 10) {
            Text(title).font(.mono(size: 12)).foregroundStyle(settingsPrimary)
                .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
            if let detail {
                Text(detail).font(.system(size: 11).monospacedDigit()).foregroundStyle(settingsTertiary)
            }
            Spacer(minLength: 8)
            controls
        }
        .padding(.horizontal, 10).frame(minHeight: 30)
        .accessibilityElement(children: .contain)
    }
}
