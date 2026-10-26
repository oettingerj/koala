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
        if windows.isEmpty { newWindow(nil) }
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

    @objc func showSettings(_ sender: Any?) {}

    private func openWindow(url: URL?) {
        let controller = BrowserWindowController(initialURL: url)
        controller.onClose = { [weak self] closed in self?.windows.removeAll { $0 === closed } }
        if let previous = NSApp.keyWindow, previous.windowController is BrowserWindowController {
            controller.window?.setFrameTopLeftPoint(previous.cascadeTopLeft(from: NSPoint(x: previous.frame.minX, y: previous.frame.maxY)))
        }
        windows.append(controller)
        controller.showWindow(nil)
    }
}
