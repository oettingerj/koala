import AppKit
import BrowserKit
import WebKit

/// One browser window: tab strip in the titlebar, toolbar, and the selected tab's page.
final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    let tabs = TabCollection()
    private let rootView: BrowserRootView
    private var selectionObservation: ObservationLoop?
    private var titleObservation: ObservationLoop?
    private var sessionObservation: ObservationLoop?
    private var bookmarkObservation: ObservationLoop?
    private var extensionObservation: ObservationLoop?
    private var sleepTimer: Timer?
    private var devSessions: [UUID: DevPanelModel] = [:]
    private var detachedTools: [UUID: DevToolsWindowController] = [:]

    /// Puts background tabs to sleep after the idle time set in Settings (30 minutes by default).
    /// Pinned tabs, split panes, and pages using the camera, microphone, playing audio, or holding
    /// typed text stay awake.
    private func sleepIdleTabs() {
        let minutes = Preferences.tabSleepMinutes
        guard minutes > 0 else { return }
        let sleepAfter = TimeInterval(minutes * 60)
        let now = Date()
        for tab in tabs.tabs where tab !== tabs.selected && !tab.isPinned && tab.splitTab == nil {
            guard devSessions[tab.id]?.isPresented != true else { continue }
            guard let webView = tab.webView, now.timeIntervalSince(tab.lastActiveAt) > sleepAfter, !tab.isPlayingAudio,
                  webView.cameraCaptureState == .none, webView.microphoneCaptureState == .none else { continue }
            Task { [weak tab, weak self] in
                guard await webView.requestMediaPlaybackState() != .playing,
                      let tab, await !tab.hasUnsavedInput(), self?.tabs.selected !== tab else { return }
                tab.sleep()
            }
        }
    }
    private var reportedTabs: [UUID: Tab] = [:]
    private weak var reportedActive: Tab?

    /// Tells loaded extensions which tabs opened, closed, or became active.
    private func reportTabChangesToExtensions() {
        guard !isPrivate else { return }
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
    /// A private window keeps no history, session, favicons, or recently closed tabs, and its
    /// pages use an in-memory data store shared with other private windows. Extensions don't see it.
    let isPrivate: Bool
    private let privateConfiguration: WKWebViewConfiguration?
    /// Private windows share one in-memory data store, so a tab moves between them with its
    /// session. It goes away when the last private window closes.
    private static weak var sharedPrivateConfiguration: WKWebViewConfiguration?
    /// A private window's camera and microphone choices, forgotten when it closes.
    private var privateMediaDecisions: [String: Bool] = [:]

    /// Opens a window with one tab at `initialURL` (blank when nil), the tabs of `snapshot`, or
    /// `tab`, torn off another window.
    init(initialURL: URL? = nil, snapshot: WindowSnapshot? = nil, isPrivate: Bool = false, adopting tab: Tab? = nil) {
        self.isPrivate = isPrivate
        if isPrivate {
            let configuration = Self.sharedPrivateConfiguration ?? WebViewFactory.makePrivateConfiguration()
            Self.sharedPrivateConfiguration = configuration
            privateConfiguration = configuration
        } else {
            privateConfiguration = nil
        }
        rootView = BrowserRootView(tabs: tabs)
        rootView.toolbar.isPrivate = isPrivate
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
        rootView.strip.onTearOff = { [weak self] tab, point in self?.tearOff(tab, at: point) }
        rootView.toolbar.addressField.onSubmit = { [weak self] text in self?.navigate(to: text) }
        rootView.toolbar.addressField.onCancel = { [weak self] in self?.focusPage() }
        rootView.toolbar.addressField.onToggleBookmark = { [weak self] in self?.toggleBookmark(nil) }
        let field = rootView.toolbar.addressField
        field.onTextChange = { [weak self, weak field] text, edit in
            guard let self, let field else { return nil }
            addressDropdown.update(query: text, edit: edit, anchor: field)
            return addressDropdown.model.inline?.text
        }
        addressDropdown.model.onLeaveCompletion = { [weak field] in field?.clearCompletion() }
        field.onMoveSelection = { [weak self] step in self?.addressDropdown.moveSelection(by: step) ?? false }
        field.onSubmitSelection = { [weak self] newTab in self?.addressDropdown.activateSelected(newTab: newTab) ?? false }
        field.onEndEditing = { [weak self] in self?.addressDropdown.hide() }
        rootView.bookmarksBar.onOpen = { [weak self] url, newTab in self?.openBookmark(url, newTab: newTab) }

        if let tab {
            tabs.insert(adopt(tab), select: true)
            services.applyCachedFavicon(to: tab)
        } else if let snapshot, !snapshot.tabs.isEmpty {
            for tabSnapshot in snapshot.tabs {
                let tab = adopt(Tab(snapshot: tabSnapshot))
                tabs.insert(tab, select: false)
                services.applyCachedFavicon(to: tab)
            }
            tabs.select(at: snapshot.selectedIndex ?? 0)
        } else {
            openTab(url: initialURL, select: true)
            if initialURL == nil { focusAddressField() }
        }

        selectionObservation = ObservationLoop { [weak self] in self?.showSelectedTab() }
        titleObservation = ObservationLoop { [weak self] in self?.updateWindowTitle() }
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
    private let popover = PopoverPresenter()
    private var signInPanel: NSPanel?

    @objc func showGitHubContext(_ sender: Any?) {
        guard let tab = tabs.focused, let page = GitHubURL(tab.url) else { return }
        let view = GitHubContextPopover(github: page, status: github.status(for: tab.url), isSignedIn: github.isSignedIn) { [weak self] action in
            self?.popover.close()
            self?.performGitHub(action, page: page)
        }
        GitHubHosting.show(view, in: popover, from: rootView.toolbar.addressField)
    }

    @objc func showReviewQueue(_ sender: Any?) {
        let view = ReviewQueuePopover(items: github.queue, isSignedIn: github.isSignedIn,
                                      open: { [weak self] url in self?.popover.close(); self?.openTab(url: url, select: true, opener: self?.tabs.selected) },
                                      signIn: { [weak self] in self?.popover.close(); self?.signInToGitHub(nil) })
        GitHubHosting.show(view, in: popover, from: rootView.toolbar.queueButton)
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

    /// Opens the first failing check's page; for GitHub Actions that is the job's log.
    @objc func openFailingCheck(_ sender: Any?) {
        guard let url = failingCheckURL else { return NSSound.beep() }
        openTab(url: url, select: true, opener: tabs.focused)
    }

    private var failingCheckURL: URL? {
        github.status(for: tabs.focused?.url)?.checkRuns.first { $0.result == .failing }?.url
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
        DownloadsHosting.show(view, in: popover, from: button.isHidden ? rootView.toolbar.addressField : button)
    }

    @objc func printPage(_ sender: Any?) {
        guard let webView = tabs.focused?.webView, let window else { return }
        let operation = webView.printOperation(with: .shared)
        operation.view?.frame = webView.bounds
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    @objc func showFindBar(_ sender: Any?) {
        // A native page has nothing to find in; Settings searches its own rows.
        if let tab = tabs.focused, tab.page != nil || tab.isHome { return focusPage() }
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
    private func applySiteZoom(to tab: Tab) {
        guard let host = DisplayURL(tab.url)?.host, let webView = tab.webView else { return }
        let zoom = CGFloat(SiteZoom.shared[host])
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
            split(tab, with: url)
        case .switchToTab(let id):
            guard let partner = tabs.tabs.first(where: { $0.id == id }), partner !== tab else { return NSSound.beep() }
            if partner.splitTab != nil { tabs.unsplit(partner) }
            tabs.split(tab, with: partner)
        case .command, .reopenClosed:
            NSSound.beep()
        }
    }

    /// Opens `url` beside `tab`, replacing the other page if `tab` is already split.
    private func split(_ tab: Tab, with url: URL) {
        if tab.splitTab != nil { tabs.unsplit(tab) }
        tabs.split(tab, with: adopt(Tab(url: url)))
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
            partner.close()
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
        let tab = adopt(Tab(adopting: webView, openerID: tabs.selected?.id))
        tabs.insert(tab, select: true)
        services.applyCachedFavicon(to: tab)
    }

    func openPeekInSplit(_ webView: WKWebView) {
        guard let tab = tabs.selected else { return }
        let partner = adopt(Tab(adopting: webView, openerID: nil))
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
            openTab(url: url, select: false, opener: tabs.selected)
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
                _ = try? await library.add(title: tab.displayTitle, url: url)
            }
        }
    }

    /// Adds an empty folder at the end of the bookmarks bar.
    @objc func newBookmarkFolder(_ sender: Any?) {
        guard let window else { return }
        BookmarkMenus.newFolder(in: nil, library: services.bookmarks, in: window)
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

    /// Searches the Settings page in this window's focused tab for `query`.
    func searchSettings(_ query: String) {
        guard let tab = tabs.focused, tab.page == .settings else { return }
        (pageView(for: tab) as? SettingsHostingView)?.search(query)
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
        let tab = adopt(Tab(url: url, openerID: opener?.id))
        tabs.insert(tab, select: select)
        return tab
    }

    /// Makes this window the tab's host. Every tab this window shows comes through here.
    @discardableResult
    private func adopt(_ tab: Tab) -> Tab {
        for pane in [tab, tab.splitTab].compactMap(\.self) {
            pane.delegate = self
            pane.uiHost = self
            pane.baseConfiguration = privateConfiguration
        }
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

    /// A tab dragged out of the strip moves into the strip it was dropped on, or into a new window
    /// there. Tabs never move between private and regular windows: their data stores differ.
    private func tearOff(_ tab: Tab, at point: NSPoint) {
        let target = NSApp.orderedWindows.lazy.compactMap { $0.windowController as? BrowserWindowController }
            .first { $0 !== self && $0.isPrivate == self.isPrivate && $0.rootView.strip.contains(screenPoint: point) }
        // A window's only tab dropped nowhere stays put: the window is already where it is.
        guard target != nil || tabs.tabs.count > 1 else { return }
        release(tab)
        if let target {
            target.tabs.insert(target.adopt(tab), select: true)
            target.window?.makeKeyAndOrderFront(nil)
        } else {
            (NSApp.delegate as? AppDelegate)?.openWindow(adopting: tab, at: point, isPrivate: isPrivate)
        }
        if tabs.tabs.isEmpty { window?.close() }
    }

    /// Takes `tab` out of this window without closing it, so another window can show it.
    private func release(_ tab: Tab) {
        for pane in [tab, tab.splitTab].compactMap(\.self) {
            closeDevTools(for: pane)
            pane.webView?.removeFromSuperview()
        }
        tabs.remove(tab)
    }

    func close(_ tab: Tab) {
        closeDevTools(for: tab)
        if let partner = tab.splitTab { closeDevTools(for: partner) }
        if !isPrivate, tabs.tabs.count > 1, tab.url != nil, let index = tabs.index(of: tab) {
            services.remember(.tab(tab.snapshot, index: index))
        }
        tab.close()
        tab.splitTab?.close()
        tabs.remove(tab)
        if tabs.tabs.isEmpty { window?.close() }
    }

    private weak var shownTab: Tab?
    private weak var shownSplit: Tab?
    /// A tab swaps its web view when it moves between the web and an extension's pages, or to a native page.
    private weak var shownWebView: NSView?
    private weak var shownSplitWebView: NSView?
    /// Hosting views for tabs showing a native page (Settings, or the home page of a blank tab),
    /// kept while the tab shows that page.
    private var nativeViews: [Tab.ID: (page: KoalaPage?, view: NSView)] = [:]

    /// The view that shows `tab`: its native page, the home page while it is blank, or its web view
    /// (created on first use).
    private func pageView(for tab: Tab) -> NSView {
        let page = tab.page
        guard page != nil || tab.isHome else {
            nativeViews[tab.id] = nil
            return tab.materialize()
        }
        if let native = nativeViews[tab.id], native.page == page { return native.view }
        // Drop views of native tabs that closed or moved to another window.
        let live = Set(tabs.tabs.flatMap { [$0.id, $0.splitTab?.id].compactMap(\.self) })
        nativeViews = nativeViews.filter { live.contains($0.key) }
        let open: (URL, Bool) -> Void = { [weak self] url, newTab in self?.openBookmark(url, newTab: newTab) }
        let view: NSView = switch page {
        case .settings: SettingsPage.host()
        case .history: HistoryHostingView.make(open: open)
        case .bookmarks: BookmarksHostingView.make(open: open)
        case nil: HomeHostingView.make { [weak self] url, target in
            switch target {
            case .newTab: _ = self?.openTab(url: url, select: true, opener: self?.tabs.selected)
            case .backgroundTab: self?.openBookmark(url, newTab: true)
            case .here: self?.openBookmark(url, newTab: false)
            }
        }
        }
        nativeViews[tab.id] = (page, view)
        return view
    }

    /// The home page in view, when the focused tab is blank.
    private var shownHome: RefreshablePage? {
        guard let tab = tabs.focused, tab.isHome else { return nil }
        return nativeViews[tab.id]?.view as? RefreshablePage
    }

    /// Apart from `showSelectedTab` so title changes while a page loads don't re-run it.
    private func updateWindowTitle() {
        guard let tab = tabs.selected else { return }
        window?.title = isPrivate ? "\(tab.displayTitle) — Private" : tab.displayTitle
    }

    private func showSelectedTab() {
        guard let tab = tabs.selected else { return }
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
        updateHandoff()
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
        let tab = adopt(Tab(snapshot: snapshot))
        tab.openerID = nil
        tabs.insert(tab, select: true)
        tabs.move(tab, to: index)
        services.applyCachedFavicon(to: tab)
    }

    private func focusAddressField() {
        DispatchQueue.main.async { [weak self] in self?.rootView.toolbar.addressField.focus() }
    }

    func focusPage() {
        guard let tab = tabs.focused else { return }
        if tab.page != nil || tab.isHome {
            // The page focuses its search field once it is in the window.
            (pageView(for: tab) as? SearchablePage)?.focusSearch()
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
        menu.addItem(closureMenuItem(tab.isMuted ? "Unmute Tab" : "Mute Tab") { tab.setMuted(!tab.isMuted) })
        if let url = tab.url {
            menu.addItem(.separator())
            menu.addItem(closureMenuItem("Copy Link") { Pasteboard.copy(url: url, title: tab.title) })
            if tab.page == nil {
                menu.addItem(closureMenuItem("Share…") { [weak self] in
                    guard let anchor = self?.rootView.strip.view(for: tab) else { return }
                    NSSharingServicePicker(items: [url]).show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
                })
            }
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
        let copy = adopt(Tab(snapshot: snapshot))
        copy.openerID = tab.id
        tabs.insert(copy, select: true)
        services.applyCachedFavicon(to: copy)
    }

    private func closeTabs(where predicate: (Tab) -> Bool) {
        for tab in tabs.tabs where predicate(tab) { close(tab) }
    }

    // MARK: Menu actions

    @objc func sharePage(_ sender: Any?) {
        guard let url = tabs.focused?.url else { return }
        let field = rootView.toolbar.addressField
        NSSharingServicePicker(items: [url]).show(relativeTo: field.bounds, of: field, preferredEdge: .minY)
    }

    // MARK: Handoff

    /// Offers the page in view to the user's other devices.
    private lazy var handoff = NSUserActivity(activityType: NSUserActivityTypeBrowsingWeb)

    /// Called when the window becomes key and when its page changes. Private windows, native pages,
    /// and non-web pages offer nothing.
    private func updateHandoff() {
        guard window?.isKeyWindow == true else { return }
        guard !isPrivate, let tab = tabs.focused, tab.page == nil, let url = tab.url,
              url.scheme == "http" || url.scheme == "https" else { return handoff.resignCurrent() }
        handoff.webpageURL = url
        handoff.title = tab.displayTitle
        handoff.becomeCurrent()
    }

    @objc func copyURL(_ sender: Any?) {
        guard let tab = tabs.focused, let url = tab.url else { return }
        Pasteboard.copy(url: url, title: tab.title)
    }

    @objc func togglePinTab(_ sender: Any?) {
        if let tab = tabs.selected { tabs.setPinned(tab, !tab.isPinned) }
    }

    @objc func toggleMuteTab(_ sender: Any?) {
        if let tab = tabs.selected { tab.setMuted(!tab.isMuted) }
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
                let tab = openTab(url: nil, select: true, opener: tabs.selected)
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
        case .reopenClosed(let index):
            (NSApp.delegate as? AppDelegate)?.reopenClosed(at: index)
        }
    }

    @objc func copyMarkdownLink(_ sender: Any?) {
        guard let tab = tabs.focused, let url = tab.url else { return }
        copyMarkdownLink(url, title: tab.displayTitle)
    }

    /// GitHub links read as references: "owner/repo#123: Title".
    private func copyMarkdownLink(_ url: URL, title: String) {
        var text = title
        if let page = GitHubURL(url), let number = page.number {
            text = "\(page.slug)#\(number): " + (github.status(for: url)?.title ?? GitHubURL.itemTitle(fromPageTitle: text))
        }
        copyString(markdownLink(title: text, url: url))
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
    /// On the home page ⌘R refreshes what it shows; a blank tab has nothing else to reload.
    @objc func reloadPage(_ sender: Any?) {
        if let home = shownHome { return home.refresh() }
        tabs.focused?.reload()
    }

    @objc func hardReload(_ sender: Any?) {
        if let home = shownHome { return home.refresh() }
        tabs.focused?.reload(fromOrigin: true)
    }
    @objc func stopLoading(_ sender: Any?) { tabs.focused?.stop() }

    @objc func reloadOrStop(_ sender: Any?) {
        guard let tab = tabs.focused else { return }
        if let home = shownHome { return home.refresh() }
        if tab.isLoading { tab.stop() } else { tab.reload() }
    }

    @objc func zoomIn(_ sender: Any?) { adjustZoom { min($0 + 0.1, 3) } }
    @objc func zoomOut(_ sender: Any?) { adjustZoom { max($0 - 0.1, 0.3) } }
    @objc func actualSize(_ sender: Any?) { adjustZoom { _ in 1 } }

    private func adjustZoom(_ transform: (CGFloat) -> CGFloat) {
        guard let tab = tabs.focused, let webView = tab.webView else { return }
        webView.pageZoom = (transform(webView.pageZoom) * 10).rounded() / 10
        if !isPrivate, let host = DisplayURL(tab.url)?.host {
            SiteZoom.shared[host] = Double(webView.pageZoom)
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
        case #selector(reloadPage(_:)), #selector(hardReload(_:)):
            return tabs.focused?.page == nil
        case #selector(zoomIn(_:)), #selector(zoomOut(_:)), #selector(actualSize(_:)), #selector(printPage(_:)), #selector(viewSource(_:)):
            return tabs.focused.map { $0.page == nil && !$0.isHome } ?? false
        case #selector(selectTabByNumber(_:)): return item.tag == 9 ? !tabs.tabs.isEmpty : item.tag <= tabs.tabs.count
        case #selector(copyPermalink(_:)):
            if case .blob = GitHubURL(tabs.focused?.url)?.kind { return true }
            return false
        case #selector(showGitHubContext(_:)):
            return GitHubURL(tabs.focused?.url) != nil
        case #selector(copyCheckoutCommand(_:)):
            if case .pullRequest = GitHubURL(tabs.focused?.url)?.kind { return true }
            return false
        case #selector(openFailingCheck(_:)): return failingCheckURL != nil
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
        case #selector(sharePage(_:)):
            return tabs.focused?.url != nil && tabs.focused?.page == nil
        case #selector(toggleMuteTab(_:)):
            item.title = tabs.selected?.isMuted == true ? "Unmute Tab" : "Mute Tab"
            return tabs.selected != nil
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
    func windowDidBecomeKey(_ notification: Notification) {
        if !isPrivate { ExtensionsHost.shared.didFocus(self) }
        updateHandoff()
    }
    func windowWillExitFullScreen(_ notification: Notification) { rootView.isFullScreen = false }

    func windowWillClose(_ notification: Notification) {
        for session in devSessions.values { session.close() }
        for controller in detachedTools.values { controller.onClose = nil; controller.close() }
        detachedTools.removeAll(); devSessions.removeAll()
        closeSignInPanel()
        if !isPrivate, !isDisposable, tabs.tabs.count > 0 {
            if tabs.tabs.count == 1, let tab = tabs.tabs.first {
                services.remember(.tab(tab.snapshot, index: 0))
            } else {
                services.remember(.window(snapshot))
            }
        }
        for tab in tabs.tabs {
            if !isPrivate { ExtensionsHost.shared.didClose(tab, windowIsClosing: true) }
            tab.close()
            tab.splitTab?.close()
        }
        if !isPrivate { ExtensionsHost.shared.didClose(self) }
        extensionObservation?.cancel()
        sleepTimer?.invalidate()
        selectionObservation?.cancel()
        titleObservation?.cancel()
        sessionObservation?.cancel()
        bookmarkObservation?.cancel()
        onClose?(self)
    }
}

#if DEBUG
/// Review hooks: type into the command bar or address field and capture its suggestions.
extension BrowserWindowController {
    func reviewCommandBar(query: String) {
        guard let window else { return }
        if !commandBar.isVisible {
            services.commands = MenuCommands.collect()
            commandBar.show(over: window, chromeHeight: rootView.chromeHeight)
        }
        commandBar.reviewType(query)
    }

    /// Tears off the selected tab: "away" drops it clear of every window, "back" onto another window's strip.
    func reviewTearOff(_ destination: String) {
        guard let tab = tabs.selected else { return }
        let others = NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }.filter { $0 !== self }
        if destination == "back", let target = others.first, let strip = target.window.map({ _ in target.rootView.strip }),
           let targetWindow = target.window {
            let center = strip.convert(NSPoint(x: strip.bounds.midX, y: strip.bounds.midY), to: nil)
            tearOff(tab, at: targetWindow.convertPoint(toScreen: center))
        } else {
            let screen = window?.screen?.visibleFrame ?? .zero
            tearOff(tab, at: NSPoint(x: screen.minX + 160, y: screen.maxY - 120))
        }
    }

    func reviewAddressField(query: String) {
        rootView.toolbar.addressField.reviewType(query)
    }

    func reviewSuggestionsSnapshot(name: String) {
        let view = commandBar.isVisible ? commandBar.reviewView : addressDropdown.reviewView
        guard let view else { return }
        try? ReviewSnapshot.save(view, folder: "suggestions", name: "\(name)-\(ReviewSnapshot.appearanceName(view))")
    }
}
#endif

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
        let permissions = SitePermissions.shared
        let key = SitePermissions.key(origin: origin, type: type)
        if let decision = privateMediaDecisions[key] ?? permissions.decision(origin: origin, type: type) { return decision }
        let alert = NSAlert()
        alert.messageText = "Allow \(origin) to use your \(SitePermissions.deviceName(type).lowercased())?"
        alert.informativeText = "Koala remembers your choice for this site. You can change it in Settings › Sites."
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Don’t Allow")
        let allowed = await sheet(alert) == .alertFirstButtonReturn
        if isPrivate { privateMediaDecisions[key] = allowed } else { permissions.set(allowed, origin: origin, type: type) }
        return allowed
    }

    func tab(_ tab: Tab, credentialFor space: URLProtectionSpace, failures: Int) async -> URLCredential? {
        let host = [0, 80, 443].contains(space.port) ? space.host : "\(space.host):\(space.port)"
        let alert = NSAlert()
        alert.messageText = failures == 0 ? "Sign in to \(host)" : "Couldn’t sign in to \(host). Try again?"
        var notes: [String] = []
        if let realm = space.realm, !realm.isEmpty { notes.append("The site says: “\(realm)”") }
        if !space.receivesCredentialSecurely { notes.append("Your password will be sent without encryption.") }
        alert.informativeText = notes.joined(separator: "\n")
        let user = NSTextField(string: "")
        user.placeholderString = "User name"
        let password = NSSecureTextField(string: "")
        password.placeholderString = "Password"
        let fields = NSStackView(views: [user, password])
        fields.orientation = .vertical
        fields.spacing = 8
        fields.frame = NSRect(x: 0, y: 0, width: 280, height: 52)
        for field in [user, password] { field.widthAnchor.constraint(equalToConstant: 280).isActive = true }
        alert.accessoryView = fields
        alert.addButton(withTitle: "Sign In")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = user
        guard await sheet(alert) == .alertFirstButtonReturn else { return nil }
        return URLCredential(user: user.stringValue, password: password.stringValue, persistence: .forSession)
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

    /// Pages can't launch apps unasked. One prompt at a time: Zoom's page fires its link on load and again on click.
    func tab(_ tab: Tab, openExternally url: URL, in app: URL) {
        guard let window, window.attachedSheet == nil else { return }
        let name = ExternalApp.displayName(of: app)
        let alert = NSAlert()
        alert.messageText = "Open \(name)?"
        let host = tab.url?.host() ?? ""
        alert.informativeText = host.isEmpty ? "This page wants to open \(name)." : "\(host) wants to open \(name)."
        alert.icon = NSWorkspace.shared.icon(forFile: app.path)
        alert.addButton(withTitle: "Open \(name)")
        alert.addButton(withTitle: "Cancel")
        Task {
            if await sheet(alert) == .alertFirstButtonReturn { NSWorkspace.shared.open(url) }
        }
    }
}

extension BrowserWindowController: TabDelegate {
    func tab(_ tab: Tab, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction) -> WKWebView? {
        // A new window for an app link would stay blank once the app takes it.
        if let url = action.request.url, let app = ExternalApp.handler(for: url) {
            self.tab(tab, openExternally: url, in: app)
            return nil
        }
        let webView = WebViewFactory.makeWebView(configuration: configuration)
        let child = adopt(Tab(adopting: webView, openerID: tab.id))
        tabs.insert(child, select: !action.modifierFlags.contains(.command))
        return webView
    }

    func tab(_ tab: Tab, openInNewTab url: URL, inBackground: Bool) {
        openTab(url: url, select: !inBackground, opener: tab)
    }

    func tabDidRequestClose(_ tab: Tab) {
        if let owner = tabs.tabs.first(where: { $0.splitTab === tab }) {
            tabs.unsplit(owner, keepingPartner: false)
            tab.close()
        } else {
            close(tab)
        }
    }

    func tabWebContentProcessDidTerminate(_ tab: Tab) {
        let inView = tabs.selected === tab || tabs.selected?.splitTab === tab
        if inView { tab.recoverFromCrash() } else { tab.sleep() }
    }

    /// Koala's link actions go after WebKit's "Open Link in New Window", which opens a tab here.
    func tab(_ tab: Tab, willOpenMenu menu: NSMenu, for link: KoalaWebView.ContextLink) {
        let openIdentifier = NSUserInterfaceItemIdentifier("WKMenuItemIdentifierOpenLinkInNewWindow")
        guard let open = menu.items.firstIndex(where: { $0.identifier == openIdentifier }) else { return }
        menu.items[open].title = "Open Link in New Tab"
        let url = link.url
        let items = [
            closureMenuItem("Open Link in Peek") { [weak self] in self?.tab(tab, peek: url) },
            closureMenuItem("Open Link in Split View") { [weak self] in
                guard let self, let owner = tabs.tabs.first(where: { $0 === tab || $0.splitTab === tab }) else { return }
                split(owner, with: url)
            },
            closureMenuItem("Copy Link as Markdown") { [weak self] in
                self?.copyMarkdownLink(url, title: link.text.isEmpty ? url.absoluteString : link.text)
            },
        ]
        for (offset, item) in items.enumerated() { menu.insertItem(item, at: open + 1 + offset) }
    }

    func tab(_ tab: Tab, peek url: URL) {
        rootView.peek.show(url: url, configuration: privateConfiguration)
    }

    func tabDidCommitNavigation(_ tab: Tab) {
        devSessions[tab.id]?.navigationDidCommit()
        services.applyCachedFavicon(to: tab)
        applySiteZoom(to: tab)
        if tab === tabs.focused { updateHandoff() }
        guard !isPrivate, let url = tab.url else { return }
        let typed = tab.nextNavigationIsTyped
        services.suggestions.noteVisit(url: url, typed: typed)
        if GitHubURL(url)?.number != nil { github.refreshSoon() }
        ExtensionsHost.shared.didChange([.URL, .loading], for: tab)
        let title = tab.title
        Task { try? await services.history.recordVisit(url: url, title: title, typed: typed) }
    }

    func tabDidFinishNavigation(_ tab: Tab) {
        if tab === tabs.focused { updateHandoff() }
        if tab.isJSONDocument {
            tab.webView?.evaluateJavaScript(PageTools.jsonViewer, in: nil, in: DevToolsScripts.world) { _ in }
        }
        guard !isPrivate else { return }
        services.refreshFavicon(for: tab)
        ExtensionsHost.shared.didChange([.title, .loading], for: tab)
        guard let url = tab.url else { return }
        let title = tab.title
        Task { try? await services.history.updateTitle(url: url, title: title) }
    }

    func tabDidChangeIconLinks(_ tab: Tab) {
        guard !isPrivate else { return }
        services.refreshFavicon(for: tab)
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
            // Out of the view tree while closed: a sheet's dimming snapshots the window every
            // frame of its animation, and a hidden hosting view still lays out and renders.
            if showsDevPanel {
                addSubview(devPanel)
                addSubview(devPanelHandle)
            } else {
                devPanel.removeFromSuperview()
                devPanelHandle.removeFromSuperview()
            }
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
        [content, strip, toolbar, bookmarksBar, findBar].forEach(addSubview)
        findBar.onVisibilityChange = { [weak self] in self?.needsLayout = true }
        splitDivider.isHidden = true
        bookmarksBar.isHidden = !showsBookmarksBar
        toolbar.showsHairline = !showsBookmarksBar
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
