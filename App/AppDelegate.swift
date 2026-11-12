import AppKit
import BrowserKit
import Eucalyptus
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [BrowserWindowController] = []
    private var dockBadgeObservation: ObservationLoop?
    /// False when launch stopped before the old sandbox data came over; nothing may be saved then.
    private var didLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard DataMigration.copyFromSandboxContainer() else { return NSApp.terminate(nil) }
        didLaunch = true
        NSApp.mainMenu = MainMenu.build()
        #if DEBUG
        DebugCommands.install()
        #endif
        let services = AppServices.shared
        Preferences.apply()
        // Extensions attach to the shared web view configuration, so they load before any page.
        ExtensionsHost.shared.anchorForAction = { context in
            let controller = (NSApp.keyWindow?.windowController as? BrowserWindowController)
                ?? NSApp.orderedWindows.lazy.compactMap { $0.windowController as? BrowserWindowController }.first
            let id = ExtensionsHost.shared.contexts.first { $0.context === context }?.id
            return controller?.extensionButton(for: id) ?? controller?.window?.contentView
        }
        dockBadgeObservation = ObservationLoop { NSApp.dockTile.badgeLabel = GitHubService.shared.dockBadge }
        services.windowSnapshots = { [weak self] in
            // Front-to-back order so the frontmost window restores on top.
            let ordered = NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
            let rest = (self?.windows ?? []).filter { controller in !ordered.contains { $0 === controller } }
            // Private windows are never restored.
            return (ordered + rest).reversed().filter { !$0.isPrivate }.map(\.snapshot)
        }
        Perf.record("launch.didFinishLaunching", Perf.sinceProcessStart)
        // Windows (chrome) appear now; pages wait for extensions so content blockers cover the
        // first load. See BrowserWindowController.showSelectedTab.
        // Recently closed comes back either way; windows only when the user wants them and
        // Koala quit recently enough.
        let session = services.loadSession()
        let maxAge = Preferences.restoreWithinMinutes > 0 ? TimeInterval(Preferences.restoreWithinMinutes * 60) : nil
        let restored = Preferences.restoresSession ? session?.restorableWindows(maxAge: maxAge) ?? [] : []
        if restored.isEmpty {
            newWindow(nil)
        } else {
            for snapshot in restored { openWindow(snapshot: snapshot) }
        }
        Perf.record("launch.windowShown", Perf.sinceProcessStart)
        Task {
            let start = ContinuousClock.now
            await ExtensionsHost.shared.start()
            Perf.record("launch.extensionsLoaded", ContinuousClock.now - start)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard didLaunch else { return }
        AppServices.shared.saveSession(sync: true)
    }

    /// ⇧⌘T: brings back the most recently closed tab or window.
    @objc func reopenClosed(_ sender: Any?) {
        reopen(AppServices.shared.takeRecentlyClosed())
    }

    @objc func reopenClosedItem(_ sender: NSMenuItem) {
        reopenClosed(at: sender.tag)
    }

    /// Reopens the recently closed item at `index`, as chosen in the menu or the command bar.
    func reopenClosed(at index: Int) {
        reopen(AppServices.shared.takeRecentlyClosed(at: index))
    }

    private func reopen(_ item: ClosedItem?) {
        switch item {
        case .tab(let snapshot, let index):
            if let controller = frontmostController {
                controller.restore(snapshot, at: index)
            } else {
                openWindow(snapshot: WindowSnapshot(frame: nil, tabs: [snapshot], selectedIndex: 0))
            }
        case .window(let snapshot):
            openWindow(snapshot: snapshot)
        case nil:
            NSSound.beep()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { newWindow(nil) }
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    /// Links opened from other apps, and from Settings, land in a new tab of the frontmost window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls { open(url) }
        NSApp.activate()
    }

    func open(_ url: URL) {
        if let controller = frontmostController {
            controller.open(url)
            controller.window?.makeKeyAndOrderFront(nil)
        } else {
            openWindow(url: url)
        }
        NSApp.activate()
    }

    private var frontmostController: BrowserWindowController? {
        if let key = NSApp.keyWindow?.windowController as? BrowserWindowController { return key }
        return NSApp.orderedWindows.lazy.compactMap { $0.windowController as? BrowserWindowController }.first
    }

    @objc func newWindow(_ sender: Any?) { openWindow(url: nil) }
    @objc func newPrivateWindow(_ sender: Any?) { openWindow(url: nil, isPrivate: true) }

    /// Settings is a page in a tab: focus the open one, else open it like any link.
    @objc func showSettings(_ sender: Any?) { show(.settings) }

    /// File › Import: Settings, searched down to the importers.
    @objc func showImport(_ sender: Any?) {
        show(.settings)
        // The page's view exists once its tab is shown, which `show` just did.
        DispatchQueue.main.async { self.frontmostController?.searchSettings("import") }
    }

    @objc func showHistory(_ sender: Any?) { show(.history) }
    @objc func showBookmarks(_ sender: Any?) { show(.bookmarks) }

    /// A native page in a tab: focus the open one, else open it like any link.
    private func show(_ page: KoalaPage) {
        if BrowserWindowController.reveal(page) { return NSApp.activate() }
        open(page.url)
    }

    @objc func clearHistory(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "Clear browsing history?"
        alert.informativeText = "Removes visited pages from history and address suggestions. Bookmarks and open tabs stay."
        let range = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 200, height: 26), pullsDown: false)
        range.addItems(withTitles: ["the last hour", "today", "all history"])
        range.selectItem(at: 2)
        alert.accessoryView = range
        alert.addButton(withTitle: "Clear History")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let since: Date? = switch range.indexOfSelectedItem {
        case 0: Date().addingTimeInterval(-3600)
        case 1: Calendar.current.startOfDay(for: Date())
        default: nil
        }
        Task { await AppServices.shared.clearHistory(since: since) }
    }

    @objc func openHistoryItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        if let controller = frontmostController { controller.open(url) } else { openWindow(url: url) }
    }

    /// A window with these pages, for extensions' windows.create.
    func openWindow(urls: [URL]) -> BrowserWindowController {
        let tabs = urls.map { TabSnapshot(id: UUID(), url: $0, title: "", isPinned: false, openerID: nil, interactionState: nil) }
        return openWindow(snapshot: tabs.isEmpty ? nil : WindowSnapshot(frame: nil, tabs: tabs, selectedIndex: 0))
    }

    /// A window for a tab torn off another, its top left near the pointer.
    func openWindow(adopting tab: Tab, at point: NSPoint, isPrivate: Bool) {
        let controller = openWindow(isPrivate: isPrivate, adopting: tab)
        controller.window?.setFrameTopLeftPoint(NSPoint(x: point.x - 100, y: point.y + 16))
    }

    @discardableResult
    private func openWindow(url: URL? = nil, snapshot: WindowSnapshot? = nil, isPrivate: Bool = false,
                            adopting tab: Tab? = nil) -> BrowserWindowController {
        let controller = BrowserWindowController(initialURL: url, snapshot: snapshot, isPrivate: isPrivate, adopting: tab)
        controller.onClose = { [weak self] closed in self?.windows.removeAll { $0 === closed } }
        if snapshot?.frame == nil, let previous = NSApp.keyWindow, previous.windowController is BrowserWindowController {
            controller.window?.setFrameTopLeftPoint(previous.cascadeTopLeft(from: NSPoint(x: previous.frame.minX, y: previous.frame.maxY)))
        }
        windows.append(controller)
        controller.showWindow(nil)
        if snapshot != nil || url != nil || tab != nil { controller.focusPage() }
        if !isPrivate { ExtensionsHost.shared.didOpen(controller) }
        return controller
    }
}
