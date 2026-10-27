import AppKit
import BrowserKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windows: [BrowserWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.mainMenu = MainMenu.build()
        #if DEBUG
        DebugCommands.install()
        #endif
        let services = AppServices.shared
        Preferences.apply()
        _ = GitHubService.shared
        services.windowSnapshots = { [weak self] in
            // Front-to-back order so the frontmost window restores on top.
            let ordered = NSApp.orderedWindows.compactMap { $0.windowController as? BrowserWindowController }
            let rest = (self?.windows ?? []).filter { controller in !ordered.contains { $0 === controller } }
            return (ordered + rest).reversed().map(\.snapshot)
        }
        if windows.isEmpty {
            let restored = services.loadSession()?.windows.filter { !$0.tabs.isEmpty } ?? []
            if restored.isEmpty {
                newWindow(nil)
            } else {
                for snapshot in restored { openWindow(snapshot: snapshot) }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppServices.shared.saveSession(sync: true)
    }

    /// ⇧⌘T: brings back the most recently closed tab or window.
    @objc func reopenClosed(_ sender: Any?) {
        reopen(AppServices.shared.takeRecentlyClosed())
    }

    @objc func reopenClosedItem(_ sender: NSMenuItem) {
        reopen(AppServices.shared.takeRecentlyClosed(at: sender.tag))
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

    /// Links opened from other apps land in a new tab of the frontmost window.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let controller = frontmostController {
                controller.open(url)
                controller.window?.makeKeyAndOrderFront(nil)
            } else {
                openWindow(url: url)
            }
        }
        NSApp.activate()
    }

    private var frontmostController: BrowserWindowController? {
        if let key = NSApp.keyWindow?.windowController as? BrowserWindowController { return key }
        return NSApp.orderedWindows.lazy.compactMap { $0.windowController as? BrowserWindowController }.first
    }

    @objc func newWindow(_ sender: Any?) { openWindow(url: nil) }

    @objc func showSettings(_ sender: Any?) {
        SettingsWindowController.shared.showWindow(nil)
        SettingsWindowController.shared.window?.center()
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
        Task { try? await AppServices.shared.history.clear(since: since) }
    }

    @objc func openHistoryItem(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        if let controller = frontmostController { controller.open(url) } else { openWindow(url: url) }
    }

    private func openWindow(url: URL? = nil, snapshot: WindowSnapshot? = nil) {
        let controller = BrowserWindowController(initialURL: url, snapshot: snapshot)
        controller.onClose = { [weak self] closed in self?.windows.removeAll { $0 === closed } }
        if snapshot?.frame == nil, let previous = NSApp.keyWindow, previous.windowController is BrowserWindowController {
            controller.window?.setFrameTopLeftPoint(previous.cascadeTopLeft(from: NSPoint(x: previous.frame.minX, y: previous.frame.maxY)))
        }
        windows.append(controller)
        controller.showWindow(nil)
        if snapshot != nil || url != nil { controller.focusPage() }
    }
}
