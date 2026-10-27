import AppKit
import BrowserKit
import Observation
import os
import WebKit

/// Loads installed web extensions into one WKWebExtensionController shared by every web view,
/// and answers the controller's questions about Nano's windows and tabs.
@MainActor
@Observable
final class ExtensionsHost: NSObject {
    static let shared = ExtensionsHost()

    private(set) var installed: [InstalledExtension] = []
    /// Loaded contexts by installed-extension id, in toolbar order.
    private(set) var contexts: [(id: String, context: WKWebExtensionContext)] = []
    /// Bumped when an action's icon, badge, or enabled state changes, so toolbars redraw.
    private(set) var actionsVersion = 0
    /// The last install failure, shown under Settings' Add section.
    private(set) var lastError: String?
    /// Why an enabled extension didn't load, by installed-extension id.
    private(set) var loadFailures: [String: String] = [:]
    private(set) var isInstalling = false
    /// Enabled extensions have loaded; pages may load.
    private(set) var isReady = false
    /// Safari extensions in installed apps, added or not.
    private(set) var safariExtensions: [SafariExtensions.Found] = []

    @ObservationIgnored let controller: WKWebExtensionController
    @ObservationIgnored private let store: ExtensionStore?
    @ObservationIgnored let log = Logger(subsystem: "com.joshoettinger.nano", category: "extensions")

    private override init() {
        // A stable identifier keeps extension storage (settings, rules) across launches.
        let key = "ExtensionControllerID"
        let id = UserDefaults.standard.string(forKey: key).flatMap(UUID.init(uuidString:)) ?? UUID()
        UserDefaults.standard.set(id.uuidString, forKey: key)
        controller = WKWebExtensionController(configuration: WKWebExtensionController.Configuration(identifier: id))
        store = try? ExtensionStore.defaultStore()
        super.init()
        controller.delegate = self
        // Must be set before any web view is created; every tab's configuration is a copy.
        WebViewFactory.configuration.webExtensionController = controller
        WebViewFactory.extensionConfiguration = { [controller] url in controller.extensionContext(for: url)?.webViewConfiguration }
    }

    /// Loads every enabled extension. Pages must not load before this returns, or content
    /// blockers miss the first page.
    func start() async {
        refreshSafariExtensions()
        guard let store else { return isReady = true }
        let saved = store.load()
        var items: [InstalledExtension] = []
        for item in saved {
            do {
                items.append(try await store.prepare(item))
            } catch {
                items.append(item)
                log.error("“\(item.name, privacy: .public)” couldn’t be prepared: \(error.localizedDescription, privacy: .public)")
            }
        }
        installed = items
        if items != saved { try? store.save(items) }
        for item in installed where item.isEnabled {
            await load(item)
        }
        isReady = true
    }

    // MARK: Install and manage

    func install(from url: URL) async {
        guard let store, beginInstall() else { return }
        defer { isInstalling = false }
        do {
            let name = try await store.importBundle(from: url)
            try await finishInstall(bundleName: name, chromeID: nil)
        } catch {
            fail("Couldn’t install that extension: \(error.localizedDescription)")
        }
    }

    /// Installs from a Chrome Web Store page URL or extension ID. Returns whether it installed.
    @discardableResult
    func installFromWebStore(_ text: String) async -> Bool {
        guard let store, let id = ExtensionPackage.webStoreID(from: text), let url = ExtensionPackage.webStoreDownloadURL(id: id) else {
            fail("That isn’t a Chrome Web Store extension link.")
            return false
        }
        guard beginInstall() else { return false }
        defer { isInstalling = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                fail("The Chrome Web Store didn’t return the extension.")
                return false
            }
            let name = try await store.importArchive(data)
            return try await finishInstall(bundleName: name, chromeID: id)
        } catch {
            fail("Couldn’t download that extension: \(error.localizedDescription)")
            return false
        }
    }

    func refreshSafariExtensions() {
        safariExtensions = SafariExtensions.find(in: SafariExtensions.appFolders(home: FileManager.default.homeDirectoryForCurrentUser))
    }

    /// Adds a Safari extension from its app. Its files stay in the app, so removing it deletes nothing.
    func addSafariExtension(_ found: SafariExtensions.Found) async {
        guard let store, !found.usesNativeMessaging, !installed.contains(where: { $0.safariID == found.id }), beginInstall() else { return }
        defer { isInstalling = false }
        do {
            guard let bundle = Bundle(url: found.url) else { throw SafariExtensionMissing() }
            let webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            guard await confirmInstall(webExtension) else { return }
            let item = InstalledExtension(id: UUID().uuidString, name: webExtension.displayName ?? found.appName,
                                          version: webExtension.version ?? "", bundleName: "", safariID: found.id)
            installed.append(item)
            try store.save(installed)
            await load(item, extension: webExtension)
        } catch {
            fail("Couldn’t add that extension: \(error.localizedDescription)")
        }
    }

    /// One install at a time; a new attempt clears the last one's error.
    private func beginInstall() -> Bool {
        guard !isInstalling else { return false }
        isInstalling = true
        lastError = nil
        return true
    }

    /// `chromeID` is known for Web Store installs; otherwise `prepare` reads it from the bundle.
    @discardableResult
    private func finishInstall(bundleName: String, chromeID: String?) async throws -> Bool {
        guard let store else { return false }
        var item = InstalledExtension(id: UUID().uuidString, name: "", version: "", bundleName: bundleName, chromeID: chromeID)
        let webExtension: WKWebExtension
        do {
            item = try await store.prepare(item)
            webExtension = try await WKWebExtension(resourceBaseURL: store.bundleURL(for: item))
        } catch {
            store.removeBundle(named: bundleName)
            throw error
        }
        guard await confirmInstall(webExtension, hiding: ExtensionCompatibility.addedPermissions(inBundleAt: store.bundleURL(for: item))) else {
            store.removeBundle(named: item.bundleName)
            return false
        }
        item.name = webExtension.displayName ?? "Extension"
        item.version = webExtension.version ?? ""
        installed.append(item)
        try store.save(installed)
        await load(item, extension: webExtension)
        return true
    }

    /// Shows what the extension asks for before anything runs. Permissions Nano added aren't the extension's to ask for.
    private func confirmInstall(_ webExtension: WKWebExtension, hiding added: Set<String> = []) async -> Bool {
        let alert = NSAlert()
        alert.messageText = "Add “\(webExtension.displayName ?? "this extension")”?"
        var lines: [String] = []
        let permissions = webExtension.requestedPermissions.map(\.rawValue).filter { !added.contains($0) }.sorted()
        if !permissions.isEmpty { lines.append("Permissions: " + permissions.joined(separator: ", ")) }
        let hosts = webExtension.allRequestedMatchPatterns.map(\.string).sorted()
        if hosts.contains("<all_urls>") || hosts.contains("*://*/*") {
            lines.append("It can read and change every website you visit.")
        } else if !hosts.isEmpty {
            lines.append("Websites: " + hosts.prefix(6).joined(separator: ", ") + (hosts.count > 6 ? "…" : ""))
        }
        alert.informativeText = lines.joined(separator: "\n\n")
        alert.addButton(withTitle: "Add Extension")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func load(_ item: InstalledExtension, extension provided: WKWebExtension? = nil) async {
        guard let store else { return }
        do {
            let webExtension: WKWebExtension
            if let provided {
                webExtension = provided
            } else if let safariID = item.safariID {
                guard let found = safariExtensions.first(where: { $0.id == safariID }), let bundle = Bundle(url: found.url) else {
                    throw SafariExtensionMissing()
                }
                webExtension = try await WKWebExtension(appExtensionBundle: bundle)
            } else {
                webExtension = try await WKWebExtension(resourceBaseURL: store.bundleURL(for: item))
            }
            let context = WKWebExtensionContext(for: webExtension)
            context.uniqueIdentifier = item.id
            // A fixed address keeps the extension's pages (and what they store) the same across launches.
            context.baseURL = URL(string: "webkit-extension://\(item.id.lowercased())/")!
            context.isInspectable = true
            // The user approved the requested permissions and sites when installing.
            for permission in webExtension.requestedPermissions { context.setPermissionStatus(.grantedExplicitly, for: permission) }
            for pattern in webExtension.allRequestedMatchPatterns { context.setPermissionStatus(.grantedExplicitly, for: pattern) }
            try controller.load(context)
            log.info("Loaded \(item.name, privacy: .public); permissions: \(context.grantedPermissions.keys.map(\.rawValue).sorted().joined(separator: ","), privacy: .public); errors: \(context.errors.map(\.localizedDescription).joined(separator: "; "), privacy: .public)")
            contexts.append((item.id, context))
            loadFailures[item.id] = nil
            if item.safariID == nil, ExtensionCompatibility.addedPermissions(inBundleAt: store.bundleURL(for: item)).contains("nativeMessaging") {
                nativeMessagingAddedByNano.insert(item.id)
            }
            announceOpenWindowsAndTabs(to: context)
        } catch {
            loadFailures[item.id] = error.localizedDescription
            log.error("“\(item.name, privacy: .public)” didn’t load: \(error.localizedDescription, privacy: .public)")
        }
    }

    func setEnabled(_ enabled: Bool, for item: InstalledExtension) {
        guard let index = installed.firstIndex(where: { $0.id == item.id }) else { return }
        installed[index].isEnabled = enabled
        try? store?.save(installed)
        if enabled {
            Task { await load(installed[index]) }
        } else {
            unload(item)
        }
    }

    func remove(_ item: InstalledExtension) {
        unload(item)
        installed.removeAll { $0.id == item.id }
        try? store?.save(installed)
        store?.removeBundle(named: item.bundleName)
    }

    private func unload(_ item: InstalledExtension) {
        loadFailures[item.id] = nil
        guard let entry = contexts.first(where: { $0.id == item.id }) else { return }
        try? controller.unload(entry.context)
        contexts.removeAll { $0.id == item.id }
    }

    func context(for item: InstalledExtension) -> WKWebExtensionContext? {
        contexts.first { $0.id == item.id }?.context
    }

    private func fail(_ message: String) {
        lastError = message
        log.error("\(message, privacy: .public)")
    }

    // MARK: Events from Nano

    private var windows: [BrowserWindowController] {
        NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
    }

    /// Lets a newly loaded extension see what is already open.
    private func announceOpenWindowsAndTabs(to context: WKWebExtensionContext) {
        for window in windows.reversed() {
            controller.didOpenWindow(window)
            for tab in window.tabs.tabs { controller.didOpenTab(tab) }
            if let selected = window.tabs.selected { controller.didActivateTab(selected, previousActiveTab: nil) }
        }
        controller.didFocusWindow(windows.first)
    }

    func didOpen(_ tab: Tab) { if !contexts.isEmpty { controller.didOpenTab(tab) } }
    func didClose(_ tab: Tab, windowIsClosing: Bool) { if !contexts.isEmpty { controller.didCloseTab(tab, windowIsClosing: windowIsClosing) } }
    func didActivate(_ tab: Tab, previous: Tab?) { if !contexts.isEmpty { controller.didActivateTab(tab, previousActiveTab: previous) } }
    func didChange(_ properties: WKWebExtension.TabChangedProperties, for tab: Tab) {
        if !contexts.isEmpty { controller.didChangeTabProperties(properties, for: tab) }
    }
    func didOpen(_ window: BrowserWindowController) { if !contexts.isEmpty { controller.didOpenWindow(window) } }
    func didClose(_ window: BrowserWindowController) { if !contexts.isEmpty { controller.didCloseWindow(window) } }
    func didFocus(_ window: BrowserWindowController?) { if !contexts.isEmpty { controller.didFocusWindow(window) } }

    func window(for tab: Tab) -> BrowserWindowController? {
        windows.first { $0.tabs.tabs.contains { $0 === tab } }
    }

    /// Popups anchor to the toolbar button of the extension in the key window.
    @ObservationIgnored var anchorForAction: ((WKWebExtensionContext) -> NSView?)?

    // MARK: Native messaging

    /// Open connections to native hosts. Releasing a port disconnects it, so it lives here too.
    /// Extensions whose nativeMessaging permission Nano added to reach its own hosts; real hosts stay closed to them.
    @ObservationIgnored private var nativeMessagingAddedByNano: Set<String> = []
    @ObservationIgnored fileprivate var nativePorts: [ObjectIdentifier: (port: WKWebExtension.MessagePort, connection: NativeMessagingConnection)] = [:]

    /// Launches the host `name` for an extension, if the host's manifest in Chrome's folders allows it.
    fileprivate func connectNativeHost(_ name: String?, for context: WKWebExtensionContext) throws -> NativeMessagingConnection {
        guard !nativeMessagingAddedByNano.contains(context.uniqueIdentifier) else {
            log.error("Native host \(name ?? "nil", privacy: .public) refused: the extension didn’t ask for native messaging")
            throw NativeMessaging.Failure.forbidden
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        guard let name, let host = NativeMessaging.hostManifest(named: name, in: NativeMessaging.chromeHostFolders(home: home)) else {
            log.error("Native host \(name ?? "nil", privacy: .public) not found")
            throw NativeMessaging.Failure.hostNotFound
        }
        let chromeID = installed.first(where: { $0.id == context.uniqueIdentifier })?.chromeID
        guard let chromeID, host.allows(chromeID: chromeID) else {
            log.error("Native host \(name, privacy: .public) forbids extension \(chromeID ?? "without Chrome ID", privacy: .public)")
            throw NativeMessaging.Failure.forbidden
        }
        log.info("Launching native host \(name, privacy: .public) for \(chromeID, privacy: .public)")
        return try NativeMessagingConnection(host: host, chromeID: chromeID)
    }
}

/// A Safari extension whose app was deleted or moved out of the Applications folders.
private struct SafariExtensionMissing: LocalizedError {
    var errorDescription: String? { "Its app isn’t in the Applications folder." }
}

extension ExtensionsHost: WKWebExtensionControllerDelegate {
    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        windows
    }

    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        windows.first { $0.window?.isKeyWindow == true } ?? windows.first
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewTabUsing configuration: WKWebExtension.TabConfiguration,
                                for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionTab)? {
        let target = (configuration.window as? BrowserWindowController) ?? windows.first
        guard let target else { return nil }
        let tab = target.openTab(url: configuration.url, select: configuration.shouldBeActive)
        if configuration.shouldBePinned { target.tabs.setPinned(tab, true) }
        return tab
    }

    func webExtensionController(_ controller: WKWebExtensionController, openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
                                for extensionContext: WKWebExtensionContext) async throws -> (any WKWebExtensionWindow)? {
        guard let delegate = NSApp.delegate as? AppDelegate else { return nil }
        return delegate.openWindow(urls: configuration.tabURLs)
    }

    func webExtensionController(_ controller: WKWebExtensionController, openOptionsPageFor extensionContext: WKWebExtensionContext) async throws {
        guard let url = extensionContext.optionsPageURL, let window = windows.first else { return }
        window.openTab(url: url, select: true)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissions permissions: Set<WKWebExtension.Permission>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.Permission>, Date?) {
        let names = permissions.map(\.rawValue).sorted().joined(separator: ", ")
        let granted = ask("“\(extensionContext.webExtension.displayName ?? "An extension")” wants more access", detail: names)
        return (granted ? permissions : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionToAccess urls: Set<URL>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<URL>, Date?) {
        let hosts = urls.compactMap { $0.host() }.sorted().joined(separator: ", ")
        let granted = ask("Allow “\(extensionContext.webExtension.displayName ?? "An extension")” on \(hosts)?", detail: "It will be able to read and change these pages.")
        return (granted ? urls : [], nil)
    }

    func webExtensionController(_ controller: WKWebExtensionController, promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
                                in tab: (any WKWebExtensionTab)?, for extensionContext: WKWebExtensionContext) async -> (Set<WKWebExtension.MatchPattern>, Date?) {
        let patterns = matchPatterns.map(\.string).sorted().joined(separator: ", ")
        let granted = ask("Allow “\(extensionContext.webExtension.displayName ?? "An extension")” on more sites?", detail: patterns)
        return (granted ? matchPatterns : [], nil)
    }

    private func ask(_ message: String, detail: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        return alert.runModal() == .alertFirstButtonReturn
    }

    func webExtensionController(_ controller: WKWebExtensionController, connectUsing port: WKWebExtension.MessagePort,
                                for extensionContext: WKWebExtensionContext) async throws {
        let connection = try connectNativeHost(port.applicationIdentifier, for: extensionContext)
        let key = ObjectIdentifier(port)
        nativePorts[key] = (port, connection)
        connection.onMessage = { [weak port] message in port?.sendMessage(message, completionHandler: nil) }
        connection.onClose = { [weak self, weak port] error in
            self?.log.info("Native host closed: \(error.map { "\($0)" } ?? "exited", privacy: .public)")
            port?.disconnect(throwing: error ?? NativeMessaging.Failure.hostExited)
            self?.nativePorts[key] = nil
        }
        port.messageHandler = { [weak connection] message, _ in
            if let message { connection?.send(message) }
        }
        port.disconnectHandler = { [weak self] _ in
            self?.nativePorts[key]?.connection.close()
            self?.nativePorts[key] = nil
        }
    }

    /// `runtime.sendNativeMessage`: start the host, send one message, return its first reply.
    func webExtensionController(_ controller: WKWebExtensionController, sendMessage message: Any, toApplicationWithIdentifier applicationIdentifier: String?,
                                for extensionContext: WKWebExtensionContext, replyHandler: @escaping (Any?, (any Error)?) -> Void) {
        if applicationIdentifier == ExtensionCompatibility.consoleHost {
            let entry = message as? [String: Any]
            let name = extensionContext.webExtension.displayName
            let text = "\(name ?? "Extension"): \(entry?["text"] as? String ?? "\(message)")"
            switch entry?["level"] as? String {
            case "info": log.info("\(text, privacy: .public)")
            case "warn": log.warning("\(text, privacy: .public)")
            default: log.error("\(text, privacy: .public)")
            }
            return replyHandler(nil, NativeMessaging.Failure.hostNotFound)
        }
        if applicationIdentifier == ExtensionCompatibility.fetchHost {
            Task {
                do { replyHandler(try await performBackgroundFetch(message, for: extensionContext), nil) } catch { replyHandler(nil, error) }
            }
            return
        }
        let connection: NativeMessagingConnection
        do {
            connection = try connectNativeHost(applicationIdentifier, for: extensionContext)
        } catch {
            return replyHandler(nil, error)
        }
        // Each handler clears both, which also releases the connection they capture.
        connection.onMessage = { reply in
            connection.onMessage = nil
            connection.onClose = nil
            connection.close()
            replyHandler(reply, nil)
        }
        connection.onClose = { error in
            connection.onMessage = nil
            connection.onClose = nil
            replyHandler(nil, error ?? NativeMessaging.Failure.hostExited)
        }
        connection.send(message)
    }

    func webExtensionController(_ controller: WKWebExtensionController, didUpdate action: WKWebExtension.Action, forExtensionContext context: WKWebExtensionContext) {
        actionsVersion += 1
    }

    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action,
                                for context: WKWebExtensionContext) async throws {
        guard let popover = action.popupPopover, let anchor = anchorForAction?(context) else { return }
        popover.behavior = .transient
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: anchor.isFlipped ? .maxY : .minY)
    }
}

// MARK: Nano's tabs and windows, as extensions see them

extension Tab: @retroactive WKWebExtensionTab {
    private var owner: BrowserWindowController? { ExtensionsHost.shared.window(for: self) }

    public func window(for context: WKWebExtensionContext) -> (any WKWebExtensionWindow)? { owner }
    public func indexInWindow(for context: WKWebExtensionContext) -> Int { owner?.tabs.index(of: self) ?? NSNotFound }
    public func webView(for context: WKWebExtensionContext) -> WKWebView? { webView }
    public func title(for context: WKWebExtensionContext) -> String? { displayTitle }
    public func isPinned(for context: WKWebExtensionContext) -> Bool { isPinned }
    public func url(for context: WKWebExtensionContext) -> URL? { url }
    public func isLoadingComplete(for context: WKWebExtensionContext) -> Bool { !isLoading }
    public func isSelected(for context: WKWebExtensionContext) -> Bool { owner?.tabs.selected === self }
    public func size(for context: WKWebExtensionContext) -> CGSize { webView?.bounds.size ?? .zero }
    public func zoomFactor(for context: WKWebExtensionContext) -> Double { Double(webView?.pageZoom ?? 1) }
    public func shouldGrantPermissionsOnUserGesture(for context: WKWebExtensionContext) -> Bool { true }

    public func activate(for context: WKWebExtensionContext) async throws {
        owner?.tabs.select(self)
        owner?.window?.makeKeyAndOrderFront(nil)
    }

    public func close(for context: WKWebExtensionContext) async throws { owner?.close(self) }

    public func loadURL(_ url: URL, for context: WKWebExtensionContext) async throws { load(url) }

    public func reload(fromOrigin: Bool, for context: WKWebExtensionContext) async throws { reload(fromOrigin: fromOrigin) }
    public func goBack(for context: WKWebExtensionContext) async throws { goBack() }
    public func goForward(for context: WKWebExtensionContext) async throws { goForward() }

    public func setPinned(_ pinned: Bool, for context: WKWebExtensionContext) async throws {
        owner?.tabs.setPinned(self, pinned)
    }

    public func setZoomFactor(_ zoomFactor: Double, for context: WKWebExtensionContext) async throws {
        webView?.pageZoom = CGFloat(zoomFactor)
    }
}

extension BrowserWindowController: WKWebExtensionWindow {
    func tabs(for context: WKWebExtensionContext) -> [any WKWebExtensionTab] { tabs.tabs }
    func activeTab(for context: WKWebExtensionContext) -> (any WKWebExtensionTab)? { tabs.selected }
    func windowType(for context: WKWebExtensionContext) -> WKWebExtension.WindowType { .normal }
    func isPrivate(for context: WKWebExtensionContext) -> Bool { false }

    func windowState(for context: WKWebExtensionContext) -> WKWebExtension.WindowState {
        guard let window else { return .normal }
        if window.styleMask.contains(.fullScreen) { return .fullscreen }
        if window.isMiniaturized { return .minimized }
        return window.isZoomed ? .maximized : .normal
    }

    func frame(for context: WKWebExtensionContext) -> CGRect { window?.frame ?? .null }
    func screenFrame(for context: WKWebExtensionContext) -> CGRect { window?.screen?.frame ?? .null }

    func focus(for context: WKWebExtensionContext) async throws { window?.makeKeyAndOrderFront(nil) }
    func close(for context: WKWebExtensionContext) async throws { window?.performClose(nil) }

    func setFrame(_ frame: CGRect, for context: WKWebExtensionContext) async throws {
        window?.setFrame(frame, display: true)
    }
}
