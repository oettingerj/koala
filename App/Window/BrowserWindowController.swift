import AppKit
import BrowserKit
import WebKit

/// One browser window: tab strip in the titlebar, toolbar, and the selected tab's page.
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let tabs = TabCollection()
    private let rootView: BrowserRootView
    private var selectionObservation: ObservationLoop?
    private var sessionObservation: ObservationLoop?
    private var bookmarkObservation: ObservationLoop?
    private var mediaDecisions: [String: Bool] = [:]
    private var extensionObservation: ObservationLoop?
    private var sleepTimer: Timer?
    private var devSessions: [UUID: DevPanelModel] = [:]
    private var detachedTools: [UUID: DevToolsWindowController] = [:]
    private static let sleepAfter: TimeInterval = 30 * 60

    /// Puts background tabs to sleep after 30 idle minutes. Pinned tabs, split panes, and pages
    /// using the camera, microphone, or playing audio stay awake.
    private func sleepIdleTabs() {
        let now = Date()
        for tab in tabs.tabs where tab !== tabs.selected && !tab.isPinned && tab.splitTab == nil {
            guard devSessions[tab.id]?.isPresented != true else { continue }
            guard let webView = tab.webView, now.timeIntervalSince(tab.lastActiveAt) > Self.sleepAfter,
                  webView.cameraCaptureState == .none, webView.microphoneCaptureState == .none else { continue }
            webView.requestMediaPlaybackState { [weak tab, weak self] state in
                MainActor.assumeIsolated {
                    guard let tab, state != .playing, self?.tabs.selected !== tab else { return }
                    tab.sleep()
                }
            }
        }
    }
    private var reportedTabs: [UUID: Tab] = [:]
    private weak var reportedActive: Tab?

    /// Tells loaded extensions which tabs opened, closed, or became active.
    private func reportTabChangesToExtensions() {
        let host = ExtensionsHost.shared
        let current = Dictionary(uniqueKeysWithValues: tabs.tabs.map { ($0.id, $0) })
        for (id, tab) in current where reportedTabs[id] == nil { host.didOpen(tab) }
        for (id, tab) in reportedTabs where current[id] == nil { host.didClose(tab, windowIsClosing: false) }
        reportedTabs = current
        if let selected = tabs.selected, selected !== reportedActive {
            host.didActivate(selected, previous: reportedActive)
            reportedActive = selected
        }
    }
    private lazy var commandBar: CommandBar = {
        let bar = CommandBar(engine: services.suggestions)
        bar.onActivate = { [weak self] row, _ in self?.activate(row, inNewTab: true) }
        return bar
    }()
    private lazy var addressDropdown: AddressDropdown = {
        let dropdown = AddressDropdown(engine: services.suggestions)
        dropdown.onActivate = { [weak self] row, newTab in self?.activate(row, inNewTab: newTab) }
        return dropdown
    }()
    private var services: AppServices { .shared }
    var onClose: ((BrowserWindowController) -> Void)?

    /// Opens a window with one tab at `initialURL` (blank when nil), or the tabs of `snapshot`.
    init(initialURL: URL? = nil, snapshot: WindowSnapshot? = nil) {
        rootView = BrowserRootView(tabs: tabs)
        let window = BrowserWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // An empty compact toolbar gives the titlebar the strip's 40pt height and centers the
        // traffic lights in it, natively, without repositioning the window buttons.
        window.toolbar = NSToolbar(identifier: "KoalaTitlebar")
        window.toolbarStyle = .unifiedCompact
        window.isMovableByWindowBackground = false
        // BrowserWindow moves itself; see there.
        window.isMovable = false
        window.collectionBehavior = [.fullScreenPrimary]
        window.minSize = NSSize(width: 480, height: 320)
        window.contentView = rootView
        window.tabbingMode = .disallowed
        // AppKit would otherwise focus the first text field (the address field) on show.
        window.initialFirstResponder = nil
        window.autorecalculatesKeyViewLoop = false
        super.init(window: window)
        window.delegate = self
        if let frame = snapshot?.frame {
            window.setFrame(frame, display: false)
        } else {
            window.setFrameAutosaveName("KoalaBrowserWindow")
        }

        rootView.strip.onSelect = { [weak self] tab in self?.tabs.select(tab) }
        rootView.strip.onClose = { [weak self] tab in self?.close(tab) }
        rootView.strip.menuForTab = { [weak self] tab in self?.contextMenu(for: tab) }
        rootView.toolbar.addressField.onSubmit = { [weak self] text in self?.navigate(to: text) }
        rootView.toolbar.addressField.onCancel = { [weak self] in self?.focusPage() }
        rootView.toolbar.addressField.onToggleBookmark = { [weak self] in self?.toggleBookmark(nil) }
        let field = rootView.toolbar.addressField
        field.onTextChange = { [weak self, weak field] text in
            guard let self, let field else { return }
            addressDropdown.update(query: text, anchor: field)
        }
        field.onMoveSelection = { [weak self] step in self?.addressDropdown.moveSelection(by: step) ?? false }
        field.onSubmitSelection = { [weak self] newTab in self?.addressDropdown.activateSelected(newTab: newTab) ?? false }
        field.onEndEditing = { [weak self] in self?.addressDropdown.hide() }
        rootView.bookmarksBar.onOpen = { [weak self] url, newTab in self?.openBookmark(url, newTab: newTab) }

        if let snapshot, !snapshot.tabs.isEmpty {
            for tabSnapshot in snapshot.tabs {
                let tab = Tab(snapshot: tabSnapshot)
                tab.delegate = self
                tab.uiHost = self
                tab.splitTab?.delegate = self
                tab.splitTab?.uiHost = self
                tabs.insert(tab, select: false)
                services.applyCachedFavicon(to: tab)
            }
            tabs.select(at: snapshot.selectedIndex ?? 0)
        } else {
            openTab(url: initialURL, select: true)
            if initialURL == nil { focusAddressField() }
        }

        selectionObservation = ObservationLoop { [weak self] in self?.showSelectedTab() }
        sessionObservation = ObservationLoop { [weak self] in self?.observeSessionState() }
        bookmarkObservation = ObservationLoop { [weak self] in self?.updateBookmarkStar() }
        extensionObservation = ObservationLoop { [weak self] in self?.reportTabChangesToExtensions() }
        sleepTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sleepIdleTabs() }
        }
        sleepTimer?.tolerance = 20
        rootView.peek.onOpenInTab = { [weak self] webView in self?.openPeekInTab(webView) }
        rootView.peek.onOpenInSplit = { [weak self] webView in self?.openPeekInSplit(webView) }
        rootView.onFocusPane = { [weak self] secondary in self?.tabs.focusesSplit = secondary }
        rootView.findBar.target = { [weak self] in self?.tabs.focused?.webView }
    }

    // MARK: GitHub

    private var github: GitHubService { .shared }
    private var popover: NSPopover?
    private var signInPanel: NSPanel?

    private func showPopover(_ controller: NSViewController, from view: NSView) {
        popover?.close()
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = controller
        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
        self.popover = popover
    }

    @objc func showGitHubContext(_ sender: Any?) {
        guard let tab = tabs.focused, let page = GitHubURL(tab.url) else { return }
        let view = GitHubContextPopover(github: page, status: github.status(for: tab.url), isSignedIn: github.isSignedIn,
                                        hasClone: github.clones.clone(for: page) != nil) { [weak self] action in
            self?.popover?.close()
            self?.performGitHub(action, page: page)
        }
        showPopover(GitHubHosting.contextPopover(view), from: rootView.toolbar.githubChip)
    }

    @objc func showReviewQueue(_ sender: Any?) {
        let view = ReviewQueuePopover(items: github.queue, isSignedIn: github.isSignedIn,
                                      open: { [weak self] url in self?.popover?.close(); self?.openTab(url: url, select: true) },
                                      signIn: { [weak self] in self?.popover?.close(); self?.signInToGitHub(nil) })
        showPopover(GitHubHosting.queuePopover(view), from: rootView.toolbar.queueButton)
    }

    /// A child panel rather than a sheet: the verification page opens as a tab in this window,
    /// and a sheet would block it while the code still has to be entered.
    @objc func signInToGitHub(_ sender: Any?) {
        guard let window else { return }
        if let signInPanel { signInPanel.makeKeyAndOrderFront(nil); return }
        let view = GitHubSignInView(model: GitHubSignIn(), openURL: { [weak self] url in self?.openTab(url: url, select: true) },
                                    dismiss: { [weak self] in self?.closeSignInPanel() })
        let panel = NSPanel(contentViewController: GitHubHosting.signInPanel(view))
        panel.styleMask = [.titled, .fullSizeContentView]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.becomesKeyOnlyIfNeeded = false
        let frame = window.frame
        panel.setFrameTopLeftPoint(NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - 90))
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        signInPanel = panel
    }

    private func closeSignInPanel() {
        guard let signInPanel else { return }
        window?.removeChildWindow(signInPanel)
        signInPanel.orderOut(nil)
        self.signInPanel = nil
    }

    @objc func signOutOfGitHub(_ sender: Any?) { github.signOut() }

    @objc func copyPermalink(_ sender: Any?) {
        guard let page = GitHubURL(tabs.focused?.url) else { return }
        performGitHub(.copyPermalink, page: page)
    }

    @objc func openInEditor(_ sender: Any?) {
        guard let page = GitHubURL(tabs.focused?.url) else { return }
        performGitHub(.openInEditor, page: page)
    }

    @objc func copyCheckoutCommand(_ sender: Any?) {
        guard let page = GitHubURL(tabs.focused?.url), case .pullRequest(let number) = page.kind else { return }
        performGitHub(.copyCheckout(number), page: page)
    }

    private func performGitHub(_ action: GitHubContextPopover.Action, page: GitHubURL) {
        switch action {
        case .copyBranch(let branch):
            copyString(branch)
        case .copyCheckout(let number):
            copyString("gh pr checkout \(number) --repo \(page.slug)")
        case .copyPermalink:
            guard case .blob(let ref, _, _) = page.kind else { return }
            Task {
                // Already a SHA: no lookup needed.
                let sha = ref.count == 40 && ref.allSatisfy(\.isHexDigit) ? ref
                    : try? await github.client.resolveSHA(owner: page.owner, repo: page.repo, ref: ref)
                guard let sha, let url = page.permalink(sha: sha) else { return NSSound.beep() }
                Pasteboard.copy(url: url, title: "")
            }
        case .openInEditor:
            if !github.openInEditor(page) { promptForCodeRoot(then: page) }
        case .signIn:
            signInToGitHub(nil)
        case .open(let url):
            openTab(url: url, select: true, opener: tabs.focused)
        }
    }

    private func copyString(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// No clone matched: offer to pick the code folder (once), or copy a clone command.
    private func promptForCodeRoot(then page: GitHubURL) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "No local clone of \(page.slug)"
        alert.informativeText = github.codeRoot == nil
            ? "Choose the folder where you keep your code, and Koala will find clones in it."
            : "Koala didn’t find this repository under \(github.codeRoot!.path). You can copy a clone command instead."
        if github.codeRoot == nil { alert.addButton(withTitle: "Choose Folder…") }
        alert.addButton(withTitle: "Copy Clone Command")
        alert.addButton(withTitle: "Cancel")
        let needsRoot = github.codeRoot == nil
        alert.beginSheetModal(for: window) { [weak self] response in
            if needsRoot && response == .alertFirstButtonReturn {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.prompt = "Use Folder"
                panel.begin { result in
                    guard result == .OK, let url = panel.url else { return }
                    GitHubService.shared.setCodeRoot(url)
                }
            } else if response == (needsRoot ? .alertSecondButtonReturn : .alertFirstButtonReturn) {
                self?.copyString("git clone git@github.com:\(page.slug).git")
            }
        }
    }

    // MARK: Downloads, find, zoom, import

    func extensionButton(for id: String?) -> NSView? {
        let toolbar = rootView.toolbar
        return toolbar.extensionButtons.first { $0.extensionID == id } ?? toolbar.extensionsMenuButton
    }

    @objc func showDownloads(_ sender: Any?) {
        let view = DownloadsPopover(manager: .shared) { [weak self] item in
            DownloadManager.shared.retry(item, in: self?.tabs.focused?.webView)
        }
        let button = rootView.toolbar.downloadsButton
        showPopover(DownloadsHosting.popover(view), from: button.isHidden ? rootView.toolbar.addressField : button)
    }

    @objc func printPage(_ sender: Any?) {
        guard let webView = tabs.focused?.webView, let window else { return }
        let operation = webView.printOperation(with: .shared)
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc func showFindBar(_ sender: Any?) {
        // A native page has nothing to find in; Settings searches its own rows.
        if tabs.focused?.page != nil { return focusPage() }
        rootView.findBar.show()
    }

    @objc func findNext(_ sender: Any?) { rootView.findBar.find(backwards: false) }
    @objc func findPrevious(_ sender: Any?) { rootView.findBar.find(backwards: true) }

    @objc func importFromChrome(_ sender: Any?) {
        importBrowserProfile(named: "Chrome", in: "Library/Application Support/Google/Chrome")
    }

    @objc func importFromBrave(_ sender: Any?) {
        importBrowserProfile(named: "Brave", in: "Library/Application Support/BraveSoftware/Brave-Browser")
    }

    @objc func importBookmarksFile(_ sender: Any?) {
        chooseImport(
            message: "Choose a bookmarks file: Arc’s “StorableSidebar.json”, a Chrome or Brave “Bookmarks” file, or an exported bookmarks HTML file (Safari: File › Export › Bookmarks).",
            in: "Library/Application Support", folders: false) { url in
            ImportedData(bookmarks: try BookmarkImporters.bookmarks(from: Data(contentsOf: url)))
        }
    }

    /// Chromium browsers keep each profile in its own folder: "Default", "Profile 1", and so on.
    private func importBrowserProfile(named browser: String, in folder: String) {
        chooseImport(
            message: "Choose the \(browser) profile to import, usually “Default”. Koala brings in its bookmarks and history.",
            in: folder, folders: true) { url in
            try ChromiumProfileImporter.contents(ofProfileAt: url)
        }
    }

    /// `folder` is relative to the home folder; `read` runs off the main thread.
    private func chooseImport(message: String, in folder: String, folders: Bool,
                              read: @escaping @Sendable (URL) throws -> ImportedData) {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.message = message
        panel.prompt = "Import"
        panel.canChooseDirectories = folders
        panel.canChooseFiles = !folders
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(folder)
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try await Task.detached { try read(url) }.value
                    let services = AppServices.shared
                    if !data.bookmarks.isEmpty { try await services.bookmarks.importTree(data.bookmarks) }
                    if !data.history.isEmpty {
                        try await services.history.importEntries(data.history)
                        await services.suggestions.reloadHostIndex()
                    }
                    self?.report(Self.summary(of: data))
                } catch {
                    self?.report(folders ? "Koala couldn’t find bookmarks or history in that folder."
                                         : "Koala couldn’t read that file as bookmarks.", failed: true)
                }
            }
        }
    }

    private static func summary(of data: ImportedData) -> String {
        var parts: [String] = []
        if data.bookmarkCount > 0 { parts.append("\(data.bookmarkCount) bookmarks") }
        if !data.history.isEmpty { parts.append("\(data.history.count) pages of history") }
        return parts.isEmpty ? "There was nothing to import." : "Imported \(parts.joined(separator: " and "))."
    }

    private func report(_ message: String, failed: Bool = false) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = failed ? .warning : .informational
        alert.beginSheetModal(for: window)
    }

    /// Zoom is remembered per site.
    private static var siteZoom: [String: Double] {
        get { UserDefaults.standard.dictionary(forKey: "SiteZoom") as? [String: Double] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "SiteZoom") }
    }

    private func applySiteZoom(to tab: Tab) {
        guard let host = DisplayURL(tab.url)?.host, let webView = tab.webView else { return }
        let zoom = CGFloat(Self.siteZoom[host] ?? 1)
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
    }

    // MARK: Split view and Peek

    /// "Split with…": the command bar picks the second page (an open tab or a new page).
    @objc func splitWith(_ sender: Any?) {
        guard let window, let tab = tabs.selected, tab.splitTab == nil else { return NSSound.beep() }
        services.commands = []
        commandBar.onActivate = { [weak self] row, _ in
            self?.restoreCommandBarHandler()
            self?.split(tab, with: row)
        }
        commandBar.onCancel = { [weak self] in self?.restoreCommandBarHandler() }
        commandBar.show(over: window, chromeHeight: rootView.chromeHeight, placeholder: "Split with a tab or page")
    }

    private func restoreCommandBarHandler() {
        commandBar.onActivate = { [weak self] row, _ in self?.activate(row, inNewTab: true) }
        commandBar.onCancel = nil
    }

    private func split(_ tab: Tab, with row: Suggestion) {
        switch row.action {
        case .open(let url):
            let partner = Tab(url: url)
            partner.delegate = self
            partner.uiHost = self
            tabs.split(tab, with: partner)
        case .switchToTab(let id):
            guard let partner = tabs.tabs.first(where: { $0.id == id }), partner !== tab else { return NSSound.beep() }
            if partner.splitTab != nil { tabs.unsplit(partner) }
            tabs.split(tab, with: partner)
        case .command:
            NSSound.beep()
        }
    }

    /// Turns the split back into two tabs.
    @objc func separateSplit(_ sender: Any?) {
        guard let tab = tabs.selected else { return }
        tabs.unsplit(tab)
    }

    /// Closes the focused side of a split; the other side stays as the tab.
    @objc func closeSplitPane(_ sender: Any?) {
        guard let tab = tabs.selected, let partner = tab.splitTab else { return }
        if tabs.focusesSplit {
            closeDevTools(for: partner)
            tabs.unsplit(tab, keepingPartner: false)
            partner.stop()
            partner.webView?.removeFromSuperview()
        } else {
            // Closing the left side: the right side takes the tab's place.
            let index = tabs.index(of: tab) ?? 0
            tabs.unsplit(tab, keepingPartner: true)
            close(tab)
            tabs.move(partner, to: index)
            tabs.select(partner)
        }
    }

    /// Promotes the Peek page to a tab, keeping the same web view so nothing reloads.
    func openPeekInTab(_ webView: WKWebView) {
        let tab = Tab(adopting: webView, openerID: tabs.selected?.id)
        tab.delegate = self
        tab.uiHost = self
        tabs.insert(tab, select: true)
        services.applyCachedFavicon(to: tab)
    }

    func openPeekInSplit(_ webView: WKWebView) {
        guard let tab = tabs.selected else { return }
        let partner = Tab(adopting: webView, openerID: nil)
        partner.delegate = self
        partner.uiHost = self
        if tab.splitTab != nil { tabs.unsplit(tab) }
        tabs.split(tab, with: partner)
    }

    // MARK: Dev tools

    @objc func toggleDevPanel(_ sender: Any?) {
        guard let tab = tabs.focused else { return }
        if let detached = detachedTools[tab.id] { detached.showWindow(nil); detached.window?.makeKeyAndOrderFront(nil); return }
        updateDevToolsTarget()
        rootView.showsDevPanel.toggle()
        if rootView.showsDevPanel { rootView.devPanelModel.isPresented = true }
        else { rootView.devPanelModel.close() }
    }

    @objc func viewSource(_ sender: Any?) {
        guard let tab = tabs.focused else { return }
        perform(.viewSource, session: devSession(for: tab))
    }

    func showDevPanel(section: DevPanelModel.Section) {
        updateDevToolsTarget()
        rootView.devPanelModel.section = section
        if let id = tabs.focused?.id, let detached = detachedTools[id] { detached.showWindow(nil); detached.window?.makeKeyAndOrderFront(nil); return }
        rootView.showsDevPanel = true
        rootView.devPanelModel.isPresented = true
    }

    @objc func showDevSection(_ sender: NSMenuItem) {
        guard DevPanelModel.Section.allCases.indices.contains(sender.tag) else { return }
        showDevPanel(section: DevPanelModel.Section.allCases[sender.tag])
    }

    @objc func detachDevTools(_ sender: Any?) {
        guard let tab = tabs.focused else { return }
        detach(devSession(for: tab))
    }

    private func devSession(for tab: Tab) -> DevPanelModel {
        if let session = devSessions[tab.id] { return session }
        let session = DevPanelModel(tab: tab)
        session.perform = { [weak self, weak session] action in
            guard let session else { return }
            self?.perform(action, session: session)
        }
        devSessions[tab.id] = session
        return session
    }

    private func updateDevToolsTarget() {
        guard let tab = tabs.focused else { return }
        let session = devSession(for: tab), old = rootView.devPanelModel
        if old !== session && !old.isDetached { old.close() }
        rootView.devPanelModel = session
        if session.isDetached { rootView.showsDevPanel = false }
        session.isPresented = session.isDetached || rootView.showsDevPanel
    }

    private func detach(_ session: DevPanelModel) {
        guard let tab = session.tab else { return }
        if let existing = detachedTools[tab.id] { existing.showWindow(nil); existing.window?.makeKeyAndOrderFront(nil); return }
        session.isDetached = true; session.isPresented = true
        if rootView.devPanelModel === session { rootView.showsDevPanel = false }
        let controller = DevToolsWindowController(model: session)
        controller.onClose = { [weak self, weak session] in
            session?.close(); session?.isDetached = false
            self?.detachedTools.removeValue(forKey: tab.id)
        }
        controller.onRedock = { [weak self, weak session] in if let session { self?.redock(session) } }
        detachedTools[tab.id] = controller
        controller.showWindow(nil); controller.window?.makeKeyAndOrderFront(nil)
    }

    private func redock(_ session: DevPanelModel) {
        guard let tab = session.tab else { return }
        let controller = detachedTools.removeValue(forKey: tab.id)
        controller?.onClose = nil; controller?.close()
        session.isDetached = false
        if let parent = tabs.tabs.first(where: { $0 === tab || $0.splitTab === tab }) {
            tabs.select(parent); tabs.focusesSplit = parent !== tab
        }
        rootView.devPanelModel = session; rootView.showsDevPanel = true; session.isPresented = true
        window?.makeKeyAndOrderFront(nil)
    }

    private func closeDevTools(for tab: Tab) {
        devSessions.removeValue(forKey: tab.id)?.close()
        let controller = detachedTools.removeValue(forKey: tab.id)
        controller?.onClose = nil; controller?.close()
    }

    private func perform(_ action: DevPanelModel.PageAction, session: DevPanelModel) {
        guard let tab = session.tab else { return }
        switch action {
        case .close:
            if session.isDetached { detachedTools[tab.id]?.close() }
            else { rootView.showsDevPanel = false; session.close() }
        case .detach: detach(session)
        case .redock: redock(session)
        case .hardReload:
            tab.reload(fromOrigin: true)
        case .viewSource:
            guard let webView = tab.webView, let url = tab.url else { return }
            let generation = tab.devTools.navigationID
            webView.evaluateJavaScript(PageTools.readSource, in: nil, in: DevToolsScripts.world) { [weak self] result in
                MainActor.assumeIsolated {
                    guard tab.devTools.navigationID == generation else { return }
                    guard case .success(let value) = result, let html = value as? String else {
                        session.status = "Could not read this page’s source."; return
                    }
                    guard let self else { return }
                    let source = self.openTab(url: nil, select: true, opener: tab)
                    source.loadHTML(PageTools.sourcePage(for: html, url: url), baseURL: nil,
                                    title: "Source · \(DisplayURL(url)?.host ?? url.absoluteString)")
                }
            }
        case .copyScreenshot:
            let generation = tab.devTools.navigationID
            tab.webView?.takeSnapshot(with: nil) { image, error in
                guard tab.devTools.navigationID == generation else { return }
                guard let image else { session.status = "Screenshot failed: \(error?.localizedDescription ?? "No image returned")"; return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.writeObjects([image])
                session.status = "Screenshot copied."
            }
        case .savePDF:
            guard let webView = tab.webView, let window = detachedTools[tab.id]?.window ?? window else { return }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.pdf]
            panel.nameFieldStringValue = (tab.displayTitle.isEmpty ? "Page" : tab.displayTitle) + ".pdf"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                webView.createPDF { result in
                    do {
                        let data = try result.get()
                        try data.write(to: url, options: .atomic)
                        session.status = "PDF saved."
                    } catch { session.status = "Could not save PDF: \(error.localizedDescription)" }
                }
            }
        case .clearSiteData:
            guard let host = tab.url?.host(), let window = detachedTools[tab.id]?.window ?? window else { return }
            let generation = tab.devTools.navigationID
            guard let store = tab.webView?.configuration.websiteDataStore else { return }
            let alert = NSAlert()
            alert.messageText = "Clear data for \(host)?"
            alert.informativeText = "Removes cookies, storage, and caches for this site and related site domains. You will be signed out of them."
            alert.addButton(withTitle: "Clear Data")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            alert.beginSheetModal(for: window) { response in
                guard response == .alertFirstButtonReturn else { return }
                Task { @MainActor in
                    guard tab.devTools.navigationID == generation else { session.status = "The page changed; site data was not cleared."; return }
                    let types = WKWebsiteDataStore.allWebsiteDataTypes()
                    let records = await store.dataRecords(ofTypes: types)
                    let matching = records.filter { host == $0.displayName || host.hasSuffix("." + $0.displayName) }
                    guard tab.devTools.navigationID == generation else { session.status = "The page changed; site data was not cleared."; return }
                    await store.removeData(ofTypes: types, for: matching)
                    session.refreshStorage()
                    tab.reload()
                }
            }
        }
    }

    private func updateBookmarkStar() {
        let url = tabs.focused?.url
        let field = rootView.toolbar.addressField
        field.canBookmark = url.map { $0.scheme == "http" || $0.scheme == "https" } ?? false
        field.isBookmarked = url.flatMap { services.bookmarks.bookmark(for: $0) } != nil
    }

    func openBookmark(_ url: URL, newTab: Bool) {
        if newTab {
            openTab(url: url, select: false, opener: nil)
        } else if let tab = tabs.focused {
            tab.load(url)
            focusPage()
        } else {
            openTab(url: url, select: true)
        }
    }

    @objc func toggleBookmark(_ sender: Any?) {
        guard let tab = tabs.focused, let url = tab.url, url.scheme == "http" || url.scheme == "https" else { return }
        let library = services.bookmarks
        Task {
            if let existing = library.bookmark(for: url) {
                try? await library.remove(existing)
            } else {
                try? await library.add(title: tab.displayTitle, url: url)
            }
        }
    }

    /// Adds an empty folder at the end of the bookmarks bar.
    @objc func newBookmarkFolder(_ sender: Any?) {
        guard let window else { return }
        BookmarkMenus.promptForTitle("New folder", initial: "", button: "Create", in: window) { [services] title in
            Task { try? await services.bookmarks.add(title: title, url: nil) }
        }
    }

    @objc func toggleBookmarksBar(_ sender: Any?) {
        Self.setBookmarksBar(!rootView.showsBookmarksBar)
    }

    /// The bookmarks bar is one app-wide preference, so every window follows.
    static func setBookmarksBar(_ shown: Bool) {
        for controller in NSApp.windows.compactMap({ $0.windowController as? BrowserWindowController }) {
            controller.rootView.showsBookmarksBar = shown
        }
        UserDefaults.standard.set(shown, forKey: "ShowBookmarksBar")
    }

    /// Brings forward the tab showing `page` in any window, including a split pane. Returns false when none does.
    static func reveal(_ page: KoalaPage) -> Bool {
        for controller in NSApp.orderedWindows.compactMap({ $0.windowController as? BrowserWindowController }) {
            guard let tab = controller.tabs.tabs.first(where: { $0.page == page || $0.splitTab?.page == page }) else { continue }
            controller.tabs.select(tab)
            if tab.page != page { controller.tabs.focusesSplit = true }
            controller.window?.makeKeyAndOrderFront(nil)
            controller.focusPage()
            return true
        }
        return false
    }

    /// Reads every field the session persists, so any change schedules a save.
    private func observeSessionState() {
        _ = tabs.selectedID
        for tab in tabs.tabs { _ = (tab.url, tab.title, tab.isPinned, tab.splitTab?.url, tab.splitTab?.title) }
        services.scheduleSessionSave()
    }

    var snapshot: WindowSnapshot {
        WindowSnapshot(frame: window?.frame, tabs: tabs.tabs.map(\.snapshot), selectedIndex: tabs.selectedIndex)
    }

    /// True when closing the window would lose nothing worth reopening.
    private var isDisposable: Bool {
        tabs.tabs.allSatisfy { $0.url == nil }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Tabs

    @discardableResult
    func openTab(url: URL?, select: Bool, opener: Tab? = nil) -> Tab {
        let tab = Tab(url: url, openerID: opener?.id)
        tab.delegate = self
        tab.uiHost = self
        tabs.insert(tab, select: select)
        return tab
    }

    /// Opens `url` from outside the window: reuses an untouched blank tab, else a new tab.
    func open(_ url: URL) {
        if let tab = tabs.focused, tab.url == nil, !tab.canGoBack {
            tab.load(url)
            focusPage()
        } else {
            openTab(url: url, select: true)
        }
    }

    func close(_ tab: Tab) {
        closeDevTools(for: tab)
        if let partner = tab.splitTab { closeDevTools(for: partner) }
        if tabs.tabs.count > 1, tab.url != nil, let index = tabs.index(of: tab) {
            services.remember(.tab(tab.snapshot, index: index))
        }
        tab.stop()
        tab.webView?.removeFromSuperview()
        tabs.remove(tab)
        if tabs.tabs.isEmpty { window?.close() }
    }

    private weak var shownTab: Tab?
    private weak var shownSplit: Tab?
    /// A tab swaps its web view when it moves between the web and an extension's pages, or to a native page.
    private weak var shownWebView: NSView?
    private weak var shownSplitWebView: NSView?
    /// Hosting views for tabs showing a native page (Settings), kept while the tab shows it.
    private var nativeViews: [Tab.ID: NSView] = [:]

    /// The view that shows `tab`: its native page, or its web view (created on first use).
    private func pageView(for tab: Tab) -> NSView {
        guard let page = tab.page else {
            nativeViews[tab.id] = nil
            return tab.materialize()
        }
        if let view = nativeViews[tab.id] { return view }
        // Drop views of native tabs that closed or moved to another window.
        let live = Set(tabs.tabs.flatMap { [$0.id, $0.splitTab?.id].compactMap(\.self) })
        nativeViews = nativeViews.filter { live.contains($0.key) }
        let view: NSView = switch page {
        case .settings: SettingsPage.host()
        }
        nativeViews[tab.id] = view
        return view
    }

    private func showSelectedTab() {
        guard let tab = tabs.selected else { return }
        window?.title = tab.displayTitle
        // No page loads until enabled extensions are in place; this re-runs when they are.
        guard ExtensionsHost.shared.isReady else { return }
        tab.markActive()
        let webView = pageView(for: tab)
        let partner = tab.splitTab
        partner?.delegate = self
        let partnerView = partner.map(pageView(for:))
        // Page tools read here so changing them re-runs this and applies immediately.
        for (pane, view) in [(tab, webView), (partner, partnerView)] {
            guard let pane, let view else { continue }
            view.appearance = pane.colorSchemeOverride.map { NSAppearance(named: $0 == "dark" ? .darkAqua : .aqua) } ?? nil
            _ = pane.viewportWidth
        }
        rootView.focusesSplit = tabs.focusesSplit
        updateDevToolsTarget()
        rootView.pageLayoutChanged()
        let switchedTabs = shownTab !== tab || shownSplit !== partner
        guard switchedTabs || shownWebView !== webView || shownSplitWebView !== partnerView else { return }
        if switchedTabs {
            // A playing video follows the user out of a tab it leaves view in, unless the tab was closed.
            for hidden in [shownTab, shownSplit].compactMap({ $0 }) where hidden !== tab && hidden !== partner
                && tabs.tabs.contains(where: { $0 === hidden || $0.splitTab === hidden }) {
                hidden.enterPictureInPictureIfPlaying()
            }
            tab.exitAutomaticPictureInPicture()
            partner?.exitAutomaticPictureInPicture()
        }
        shownTab = tab
        shownSplit = partner
        shownWebView = webView
        shownSplitWebView = partnerView
        Perf.measure("tab.switch") {
            rootView.show(webView, for: tab, split: partnerView.map { ($0, partner!) })
            rootView.layoutSubtreeIfNeeded()
        }
        // Switching tabs abandons whatever was typed for the previous one.
        if rootView.toolbar.addressField.isEditing, tab.url != nil {
            focusPage()
        }
    }

    private func navigate(to text: String) {
        guard let url = AddressInput.resolve(text, searchTemplate: Preferences.searchTemplate) else { return }
        let tab = tabs.focused ?? openTab(url: nil, select: true)
        tab.nextNavigationIsTyped = true
        tab.load(url)
        focusPage()
    }

    /// Reopens a closed tab where it was.
    func restore(_ snapshot: TabSnapshot, at index: Int) {
        let tab = Tab(snapshot: snapshot)
        tab.openerID = nil
        tab.delegate = self
        tab.uiHost = self
        tabs.insert(tab, select: true)
        tabs.move(tab, to: index)
        services.applyCachedFavicon(to: tab)
    }

    private func focusAddressField() {
        DispatchQueue.main.async { [weak self] in self?.rootView.toolbar.addressField.focus() }
    }

    func focusPage() {
        guard let tab = tabs.focused else { return }
        if tab.page != nil {
            // The page focuses its search field once it is in the window.
            (pageView(for: tab) as? SettingsHostingView)?.focusSearch()
        } else if let webView = tab.webView {
            window?.makeFirstResponder(webView)
        }
    }

    // MARK: Tab context menu

    private func contextMenu(for tab: Tab) -> NSMenu {
        let menu = NSMenu()
        menu.addItem(closureMenuItem(tab.isPinned ? "Unpin Tab" : "Pin Tab") { [weak self] in
            self?.tabs.setPinned(tab, !tab.isPinned)
        })
        menu.addItem(closureMenuItem("Duplicate Tab") { [weak self] in self?.duplicate(tab) })
        menu.addItem(closureMenuItem("Reload Tab") { tab.reload() })
        if let url = tab.url {
            menu.addItem(.separator())
            menu.addItem(closureMenuItem("Copy Link") { Pasteboard.copy(url: url, title: tab.title) })
        }
        menu.addItem(.separator())
        menu.addItem(closureMenuItem("Close Tab") { [weak self] in self?.close(tab) })
        menu.addItem(closureMenuItem("Close Other Tabs") { [weak self] in
            self?.closeTabs(where: { $0 !== tab && !$0.isPinned })
        })
        if let index = tabs.index(of: tab) {
            menu.addItem(closureMenuItem("Close Tabs to the Right") { [weak self] in
                guard let self else { return }
                let right = Set(tabs.tabs.dropFirst(index + 1).map(\.id))
                closeTabs(where: { right.contains($0.id) })
            })
        }
        return menu
    }

    private func duplicate(_ tab: Tab) {
        var snapshot = tab.snapshot
        snapshot.id = UUID()
        snapshot.isPinned = false
        let copy = Tab(snapshot: snapshot)
        copy.openerID = tab.id
        copy.delegate = self
        copy.uiHost = self
        tabs.insert(copy, select: true)
        services.applyCachedFavicon(to: copy)
    }

    private func closeTabs(where predicate: (Tab) -> Bool) {
        for tab in tabs.tabs where predicate(tab) { close(tab) }
    }

    // MARK: Menu actions

    @objc func copyURL(_ sender: Any?) {
        guard let tab = tabs.focused, let url = tab.url else { return }
        Pasteboard.copy(url: url, title: tab.title)
    }

    @objc func togglePinTab(_ sender: Any?) {
        if let tab = tabs.selected { tabs.setPinned(tab, !tab.isPinned) }
    }

    @objc func duplicateTab(_ sender: Any?) {
        if let tab = tabs.selected { duplicate(tab) }
    }

    /// ⌘T and the strip's + button: a blank tab with the address field focused.
    @objc func newTab(_ sender: Any?) {
        openTab(url: nil, select: true)
        focusAddressField()
    }

    /// ⌘K opens the command bar; picking a page opens it in a new tab.
    @objc func toggleCommandBar(_ sender: Any?) {
        guard let window else { return }
        if commandBar.isVisible { return commandBar.hide() }
        services.commands = MenuCommands.collect()
        commandBar.show(over: window, chromeHeight: rootView.chromeHeight)
    }

    func activate(_ row: Suggestion, inNewTab: Bool) {
        switch row.action {
        case .open(let url):
            let typed = row.kind == .navigate || row.kind == .search || row.kind == .keyword
            if inNewTab, !(tabs.focused.map { $0.url == nil && !$0.canGoBack } ?? false) {
                let tab = openTab(url: nil, select: true)
                tab.nextNavigationIsTyped = typed
                tab.load(url)
            } else {
                let tab = tabs.focused ?? openTab(url: nil, select: true)
                tab.nextNavigationIsTyped = typed
                tab.load(url)
            }
            focusPage()
        case .switchToTab(let id):
            for controller in NSApp.orderedWindows.compactMap({ $0.windowController as? BrowserWindowController }) {
                guard let tab = controller.tabs.tabs.first(where: { $0.id == id }) else { continue }
                controller.tabs.select(tab)
                controller.window?.makeKeyAndOrderFront(nil)
                controller.focusPage()
                return
            }
        case .command(let selector):
            NSApp.sendAction(NSSelectorFromString(selector), to: nil, from: self)
        }
    }

    @objc func copyMarkdownLink(_ sender: Any?) {
        guard let tab = tabs.focused, let url = tab.url else { return }
        // GitHub links read as references: "owner/repo#123: Title".
        var text = tab.displayTitle
        if let page = GitHubURL(url), let number = page.number {
            text = "\(page.slug)#\(number): " + (github.status(for: url)?.title ?? GitHubURL.itemTitle(fromPageTitle: text))
        }
        let title = text.replacingOccurrences(of: "]", with: "\\]").replacingOccurrences(of: "[", with: "\\[")
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString("[\(title)](\(url.absoluteString))", forType: .string)
    }

    /// ⌘W closes the focused side of a split first, then the tab.
    @objc func closeTab(_ sender: Any?) {
        guard let tab = tabs.selected else { return }
        if tab.splitTab != nil {
            closeSplitPane(nil)
        } else {
            close(tab)
        }
    }

    @objc func openLocation(_ sender: Any?) { focusAddressField() }
    @objc func goBack(_ sender: Any?) { tabs.focused?.goBack() }
    @objc func goForward(_ sender: Any?) { tabs.focused?.goForward() }
    @objc func reloadPage(_ sender: Any?) { tabs.focused?.reload() }
    @objc func hardReload(_ sender: Any?) { tabs.focused?.reload(fromOrigin: true) }
    @objc func stopLoading(_ sender: Any?) { tabs.focused?.stop() }

    @objc func reloadOrStop(_ sender: Any?) {
        guard let tab = tabs.focused else { return }
        if tab.isLoading { tab.stop() } else { tab.reload() }
    }

    @objc func zoomIn(_ sender: Any?) { adjustZoom { min($0 + 0.1, 3) } }
    @objc func zoomOut(_ sender: Any?) { adjustZoom { max($0 - 0.1, 0.3) } }
    @objc func actualSize(_ sender: Any?) { adjustZoom { _ in 1 } }

    private func adjustZoom(_ transform: (CGFloat) -> CGFloat) {
        guard let tab = tabs.focused, let webView = tab.webView else { return }
        webView.pageZoom = (transform(webView.pageZoom) * 10).rounded() / 10
        if let host = DisplayURL(tab.url)?.host {
            Self.siteZoom[host] = webView.pageZoom == 1 ? nil : Double(webView.pageZoom)
        }
    }

    @objc func selectNextTab(_ sender: Any?) { tabs.selectNext() }
    @objc func selectPreviousTab(_ sender: Any?) { tabs.selectPrevious() }

    /// ⌘1–⌘8 select by position; ⌘9 always selects the last tab.
    @objc func selectTabByNumber(_ sender: NSMenuItem) {
        if sender.tag == 9 { tabs.select(at: tabs.tabs.count - 1) } else { tabs.select(at: sender.tag - 1) }
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(goBack(_:)): return tabs.focused?.canGoBack ?? false
        case #selector(goForward(_:)): return tabs.focused?.canGoForward ?? false
        case #selector(stopLoading(_:)): return tabs.focused?.isLoading ?? false
        case #selector(reloadPage(_:)), #selector(hardReload(_:)), #selector(zoomIn(_:)), #selector(zoomOut(_:)),
             #selector(actualSize(_:)), #selector(printPage(_:)), #selector(viewSource(_:)):
            return tabs.focused?.page == nil
        case #selector(selectTabByNumber(_:)): return item.tag == 9 ? !tabs.tabs.isEmpty : item.tag <= tabs.tabs.count
        case #selector(copyPermalink(_:)):
            if case .blob = GitHubURL(tabs.focused?.url)?.kind { return true }
            return false
        case #selector(openInEditor(_:)), #selector(showGitHubContext(_:)):
            return GitHubURL(tabs.focused?.url) != nil
        case #selector(copyCheckoutCommand(_:)):
            if case .pullRequest = GitHubURL(tabs.focused?.url)?.kind { return true }
            return false
        case #selector(signInToGitHub(_:)): return !github.isSignedIn
        case #selector(signOutOfGitHub(_:)): return github.isSignedIn
        case #selector(findNext(_:)), #selector(findPrevious(_:)):
            return !rootView.findBar.query.isEmpty
        case #selector(separateSplit(_:)), #selector(closeSplitPane(_:)):
            return tabs.selected?.splitTab != nil
        case #selector(splitWith(_:)):
            return tabs.selected?.splitTab == nil
        case #selector(toggleDevPanel(_:)):
            item.title = rootView.showsDevPanel ? "Hide Dev Panel" : "Show Dev Panel"
            return true
        case #selector(toggleBookmarksBar(_:)):
            item.title = rootView.showsBookmarksBar ? "Hide Bookmarks Bar" : "Show Bookmarks Bar"
            return true
        case #selector(togglePinTab(_:)):
            item.title = tabs.selected?.isPinned == true ? "Unpin Tab" : "Pin Tab"
            return tabs.selected != nil
        case #selector(toggleBookmark(_:)):
            let bookmarked = tabs.focused?.url.flatMap { services.bookmarks.bookmark(for: $0) } != nil
            item.title = bookmarked ? "Remove Bookmark" : "Bookmark This Page"
            return tabs.focused?.url != nil && tabs.focused?.page == nil
        default: return true
        }
    }

    // MARK: Window

    func windowWillEnterFullScreen(_ notification: Notification) { rootView.isFullScreen = true }
    func windowDidBecomeKey(_ notification: Notification) { ExtensionsHost.shared.didFocus(self) }
    func windowWillExitFullScreen(_ notification: Notification) { rootView.isFullScreen = false }

    func windowWillClose(_ notification: Notification) {
        for session in devSessions.values { session.close() }
        for controller in detachedTools.values { controller.onClose = nil; controller.close() }
        detachedTools.removeAll(); devSessions.removeAll()
        closeSignInPanel()
        if !isDisposable, tabs.tabs.count > 0 {
            if tabs.tabs.count == 1, let tab = tabs.tabs.first {
                services.remember(.tab(tab.snapshot, index: 0))
            } else {
                services.remember(.window(snapshot))
            }
        }
        for tab in tabs.tabs {
            tab.stop()
            ExtensionsHost.shared.didClose(tab, windowIsClosing: true)
        }
        ExtensionsHost.shared.didClose(self)
        extensionObservation?.cancel()
        sleepTimer?.invalidate()
        selectionObservation?.cancel()
        sessionObservation?.cancel()
        bookmarkObservation?.cancel()
        onClose?(self)
    }
}

extension BrowserWindowController: TabUIHost {
    private func sheet(_ alert: NSAlert) async -> NSApplication.ModalResponse {
        guard let window else { return .cancel }
        return await withCheckedContinuation { continuation in
            alert.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
    }

    private func alert(_ message: String, origin: String) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = origin.isEmpty ? "This page says" : "\(origin) says"
        alert.informativeText = String(message.prefix(2000))
        return alert
    }

    func tab(_ tab: Tab, alert message: String, from origin: String) async {
        let alert = alert(message, origin: origin)
        alert.addButton(withTitle: "OK")
        _ = await sheet(alert)
    }

    func tab(_ tab: Tab, confirm message: String, from origin: String) async -> Bool {
        let alert = alert(message, origin: origin)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        return await sheet(alert) == .alertFirstButtonReturn
    }

    func tab(_ tab: Tab, prompt message: String, defaultText: String?, from origin: String) async -> String? {
        let alert = alert(message, origin: origin)
        let field = NSTextField(string: defaultText ?? "")
        field.frame = NSRect(x: 0, y: 0, width: 280, height: 22)
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        return await sheet(alert) == .alertFirstButtonReturn ? field.stringValue : nil
    }

    func tab(_ tab: Tab, chooseFiles parameters: WKOpenPanelParameters) async -> [URL]? {
        guard let window else { return nil }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        let response = await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { continuation.resume(returning: $0) }
        }
        return response == .OK ? panel.urls : nil
    }

    func tab(_ tab: Tab, allowMediaCapture type: WKMediaCaptureType, from origin: String) async -> Bool {
        let key = "\(origin)|\(type.rawValue)"
        if let decision = mediaDecisions[key] { return decision }
        let what = switch type {
        case .camera: "your camera"
        case .microphone: "your microphone"
        case .cameraAndMicrophone: "your camera and microphone"
        @unknown default: "a media device"
        }
        let alert = NSAlert()
        alert.messageText = "Allow \(origin) to use \(what)?"
        alert.informativeText = "Koala remembers your choice for this site until you quit."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        let allowed = await sheet(alert) == .alertFirstButtonReturn
        mediaDecisions[key] = allowed
        return allowed
    }

    func tab(_ tab: Tab, didStart download: WKDownload) {
        DownloadManager.shared.track(download)
        rootView.toolbar.flashDownloads()
        // A tab opened only to fetch a file has nothing to show once the download starts.
        if !tab.canGoBack, tab.title.isEmpty, tabs.tabs.count > 1, tabs.tabs.contains(where: { $0 === tab }) {
            close(tab)
        }
    }

    func tab(_ tab: Tab, save data: Data, suggestedFilename: String, from source: URL?) {
        DownloadManager.shared.save(data, suggestedFilename: suggestedFilename, from: source)
        rootView.toolbar.flashDownloads()
    }
}

extension BrowserWindowController: TabDelegate {
    func tab(_ tab: Tab, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction) -> WKWebView? {
        let webView = WebViewFactory.makeWebView(configuration: configuration)
        let child = Tab(adopting: webView, openerID: tab.id)
        child.delegate = self
        child.uiHost = self
        tabs.insert(child, select: !action.modifierFlags.contains(.command))
        return webView
    }

    func tab(_ tab: Tab, openInNewTab url: URL, inBackground: Bool) {
        openTab(url: url, select: !inBackground, opener: tab)
    }

    func tabDidRequestClose(_ tab: Tab) {
        if let owner = tabs.tabs.first(where: { $0.splitTab === tab }) {
            tabs.unsplit(owner, keepingPartner: false)
            tab.webView?.removeFromSuperview()
        } else {
            close(tab)
        }
    }

    func tab(_ tab: Tab, peek url: URL) {
        rootView.peek.show(url: url)
    }

    func tabDidCommitNavigation(_ tab: Tab) {
        devSessions[tab.id]?.navigationDidCommit()
        services.applyCachedFavicon(to: tab)
        applySiteZoom(to: tab)
        guard let url = tab.url else { return }
        if let host = DisplayURL(url)?.host { services.suggestions.noteVisit(host: host) }
        if GitHubURL(url)?.number != nil { github.refreshSoon() }
        ExtensionsHost.shared.didChange([.URL, .loading], for: tab)
        let typed = tab.nextNavigationIsTyped
        let title = tab.title
        Task { try? await services.history.recordVisit(url: url, title: title, typed: typed) }
    }

    func tabDidFinishNavigation(_ tab: Tab) {
        services.refreshFavicon(for: tab)
        ExtensionsHost.shared.didChange([.title, .loading], for: tab)
        if tab.isJSONDocument {
            tab.webView?.evaluateJavaScript(PageTools.jsonViewer, in: nil, in: DevToolsScripts.world) { _ in }
        }
        guard let url = tab.url else { return }
        let title = tab.title
        Task { try? await services.history.updateTitle(url: url, title: title) }
    }
}

/// The compact toolbar makes the whole titlebar a window-server drag region that ignores the
/// content views drawn under it, so a drag on a tab would move the window. The window server
/// can't be told otherwise per press, so the window is not movable there and instead moves
/// itself, and zooms on double-click, from chrome views that allow window moves.
/// Presses on the frame itself (the resize edges) go to AppKit.
final class BrowserWindow: NSWindow {
    override func sendEvent(_ event: NSEvent) {
        guard event.type == .leftMouseDown, !styleMask.contains(.fullScreen), let contentView,
              let root = contentView as? BrowserRootView,
              let hit = contentView.superview?.hitTest(event.locationInWindow),
              root.isWindowDragRegion(hit), hit.mouseDownCanMoveWindow
        else { return super.sendEvent(event) }
        if event.clickCount == 2 {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize" {
            case "Minimize": performMiniaturize(nil)
            case "None": break
            default: performZoom(nil)
            }
        } else {
            performDrag(with: event)
        }
    }
}

/// Stacks strip, toolbar, bookmarks bar, page, and the dev panel drawer.
/// Frame-based so window resizes cost one layout pass.
final class BrowserRootView: NSView {
    let strip: TabStripView
    let toolbar: ToolbarView
    let bookmarksBar = BookmarksBarView(library: AppServices.shared.bookmarks)
    var devPanelModel = DevPanelModel() {
        didSet { if oldValue !== devPanelModel { devPanel.rootView = DevPanel(model: devPanelModel) } }
    }
    let findBar = FindBar()
    private lazy var devPanel = DevPanel.host(model: devPanelModel)
    private let devPanelHandle = DragHandle()
    private let content = NSView()
    /// The primary pane's page: a web view, or a native page's hosting view.
    private weak var current: NSView?
    private weak var currentTab: Tab?

    /// Off by default: the page gets the space; ⇧⌘B or View › Show Bookmarks Bar turns it on.
    var showsBookmarksBar = UserDefaults.standard.object(forKey: "ShowBookmarksBar") as? Bool ?? false {
        didSet {
            UserDefaults.standard.set(showsBookmarksBar, forKey: "ShowBookmarksBar")
            bookmarksBar.isHidden = !showsBookmarksBar
            toolbar.showsHairline = !showsBookmarksBar
            needsLayout = true
        }
    }

    var showsDevPanel = false {
        didSet {
            devPanelModel.isPresented = showsDevPanel || devPanelModel.isDetached
            if !devPanelModel.isPresented { devPanelModel.close() }
            devPanel.isHidden = !showsDevPanel
            devPanelHandle.isHidden = !showsDevPanel
            needsLayout = true
        }
    }

    private var devPanelHeight = max(200, UserDefaults.standard.object(forKey: "DevPanelHeight") as? CGFloat ?? 300)

    var isFullScreen = false { didSet { strip.leadingInset = isFullScreen ? 12 : Theme.trafficLightInset } }

    init(tabs: TabCollection) {
        strip = TabStripView(tabs: tabs)
        toolbar = ToolbarView(tabs: tabs)
        super.init(frame: .zero)
        content.wantsLayer = true
        [content, strip, toolbar, bookmarksBar, findBar, devPanel, devPanelHandle].forEach(addSubview)
        findBar.onVisibilityChange = { [weak self] in self?.needsLayout = true }
        splitDivider.isHidden = true
        bookmarksBar.isHidden = !showsBookmarksBar
        toolbar.showsHairline = !showsBookmarksBar
        devPanel.isHidden = true
        devPanelHandle.isHidden = true
        devPanelHandle.onDrag = { [weak self] delta in
            guard let self else { return }
            devPanelHeight = max(200, min(bounds.height * 0.8, devPanelHeight + delta))
            UserDefaults.standard.set(devPanelHeight, forKey: "DevPanelHeight")
            needsLayout = true
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }

    /// SwiftUI hit views can allow window moves even when they contain a Button. Only the
    /// browser chrome opts into our custom window dragging; page and devtools input stays native.
    func isWindowDragRegion(_ hit: NSView) -> Bool {
        [strip, toolbar, bookmarksBar, findBar].contains { hit.isDescendant(of: $0) }
    }

    override func updateLayer() {
        // Visible around the page only in responsive mode.
        content.layer?.backgroundColor = resolved(Theme.stripGround)
    }
    override var wantsUpdateLayer: Bool { true }

    override func layout() {
        super.layout()
        let height = bounds.height
        strip.frame = NSRect(x: 0, y: height - Theme.stripHeight, width: bounds.width, height: Theme.stripHeight)
        toolbar.frame = NSRect(x: 0, y: strip.frame.minY - Theme.toolbarHeight, width: bounds.width, height: Theme.toolbarHeight)
        var contentTop = toolbar.frame.minY
        if showsBookmarksBar {
            bookmarksBar.frame = NSRect(x: 0, y: contentTop - BookmarksBarView.height, width: bounds.width, height: BookmarksBarView.height)
            contentTop = bookmarksBar.frame.minY
        }
        if !findBar.isHidden {
            findBar.frame = NSRect(x: 0, y: contentTop - FindBar.height, width: bounds.width, height: FindBar.height)
            contentTop = findBar.frame.minY
        }
        var contentBottom: CGFloat = 0
        if showsDevPanel {
            let panelHeight = min(devPanelHeight, contentTop * 0.8)
            devPanel.frame = NSRect(x: 0, y: 0, width: bounds.width, height: panelHeight)
            devPanelHandle.frame = NSRect(x: 0, y: panelHeight - 3, width: bounds.width, height: 6)
            contentBottom = panelHeight
        }
        content.frame = NSRect(x: 0, y: contentBottom, width: bounds.width, height: contentTop - contentBottom)
        layoutPage()
    }

    // MARK: Page and split panes

    private weak var splitView: NSView?
    private weak var splitTab: Tab?
    private let splitDivider = DragHandle(vertical: true)
    private let focusLine = CALayer()
    private var splitRatio: CGFloat = 0.5
    private var mouseMonitor: Any?
    let peek = PeekView()
    var focusesSplit = false { didSet { layoutPage() } }
    /// true when the user clicked into the second pane.
    var onFocusPane: ((Bool) -> Void)?

    private var primaryFrame: NSRect {
        guard splitView != nil else { return content.bounds }
        let width = (content.bounds.width * splitRatio).rounded()
        return NSRect(x: 0, y: 0, width: width, height: content.bounds.height)
    }

    private var secondaryFrame: NSRect {
        let primary = primaryFrame
        return NSRect(x: primary.maxX + 1, y: 0, width: content.bounds.width - primary.maxX - 1, height: content.bounds.height)
    }

    /// Fills each pane, or centers a page at its tab's responsive width.
    private func layoutPage() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if let current { place(current, in: primaryFrame, width: currentTab?.viewportWidth) }
        if let splitView {
            place(splitView, in: secondaryFrame, width: splitTab?.viewportWidth)
            splitDivider.isHidden = false
            splitDivider.frame = NSRect(x: primaryFrame.maxX - 2, y: 0, width: 5, height: content.bounds.height)
            focusLine.isHidden = false
            let focused = focusesSplit ? secondaryFrame : primaryFrame
            focusLine.frame = NSRect(x: focused.minX, y: focused.maxY - 2, width: focused.width, height: 2)
            focusLine.backgroundColor = resolved(Theme.accent)
        } else {
            splitDivider.isHidden = true
            focusLine.isHidden = true
        }
        peek.frame = content.bounds
    }

    private func place(_ page: NSView, in frame: NSRect, width: CGFloat?) {
        if let width, width < frame.width {
            page.frame = NSRect(x: (frame.minX + (frame.width - width) / 2).rounded(), y: 0, width: width, height: frame.height)
        } else {
            page.frame = frame
        }
    }

    func show(_ page: NSView, for tab: Tab, split: (NSView, Tab)?) {
        currentTab = tab
        if current !== page {
            current?.removeFromSuperview()
            content.addSubview(page, positioned: .below, relativeTo: splitDivider)
            current = page
        }
        if splitView !== split?.0 {
            splitView?.removeFromSuperview()
            if let view = split?.0 { content.addSubview(view, positioned: .below, relativeTo: splitDivider) }
            splitView = split?.0
        }
        splitTab = split?.1
        layoutPage()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if mouseMonitor == nil, window != nil {
            content.addSubview(splitDivider)
            content.addSubview(peek)
            content.layer?.addSublayer(focusLine)
            focusLine.zPosition = 10
            peek.isHidden = true
            splitDivider.onDrag = { [weak self] delta in
                guard let self, content.bounds.width > 0 else { return }
                splitRatio = min(0.8, max(0.2, splitRatio + delta / content.bounds.width))
                layoutPage()
            }
            // Clicking into a pane focuses it; pages swallow mouse events, so watch them here.
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
                guard let self, event.window === window, splitView != nil else { return event }
                let point = content.convert(event.locationInWindow, from: nil)
                if secondaryFrame.contains(point) { onFocusPane?(true) } else if primaryFrame.contains(point) { onFocusPane?(false) }
                return event
            }
        }
    }

    /// Height of everything above the page.
    var chromeHeight: CGFloat { bounds.height - content.frame.maxY }

    func pageLayoutChanged() { layoutPage() }
}

/// A hairline that resizes what it separates: the dev panel's top edge, or the split divider.
final class DragHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    private let vertical: Bool
    private var last: CGFloat = 0

    init(vertical: Bool = false) {
        self.vertical = vertical
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func resetCursorRects() { addCursorRect(bounds, cursor: vertical ? .resizeLeftRight : .resizeUpDown) }
    override var mouseDownCanMoveWindow: Bool { false }

    override func mouseDown(with event: NSEvent) { last = vertical ? event.locationInWindow.x : event.locationInWindow.y }

    override func mouseDragged(with event: NSEvent) {
        let position = vertical ? event.locationInWindow.x : event.locationInWindow.y
        onDrag?(position - last)
        last = position
    }

    override func draw(_ dirtyRect: NSRect) {
        Theme.hairline.setFill()
        if vertical {
            NSRect(x: bounds.midX - 0.5, y: 0, width: 1, height: bounds.height).fill()
        } else {
            NSRect(x: 0, y: bounds.midY - 0.5, width: bounds.width, height: 1).fill()
        }
    }
}
