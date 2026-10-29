#if DEBUG
import AppKit
import os

/// Debug-only: lets review scripts drive window states without UI scripting permissions.
/// Post `com.joshoettinger.koala.debug` with an object like "appearance dark",
/// "action newTab:", "open https://example.com", "resize 1280x820", "settings-search pin",
/// "snapshot-settings <suffix>", "suggest <query>" (the command bar), "suggest-address <query>",
/// "snapshot-suggestions <name>", "snapshot-window <name>", or "js return document.title"
/// (runs in the focused tab; the result goes to the log under category "debug").
@MainActor
enum DebugCommands {
    static func install() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.joshoettinger.koala.debug"), object: nil, queue: .main
        ) { note in
            let command = (note.object as? String) ?? ""
            MainActor.assumeIsolated { perform(command) }
        }
    }

    private static func perform(_ command: String) {
        let parts = command.split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = parts.first else { return }
        let argument = parts.count > 1 ? parts[1] : ""
        let window = NSApp.orderedWindows.first { $0.windowController is BrowserWindowController }
        switch verb {
        case "appearance":
            NSApp.appearance = argument == "dark" ? NSAppearance(named: .darkAqua)
                : argument == "light" ? NSAppearance(named: .aqua) : nil
        case "action":
            // Straight to the front browser window: review runs while another app is active.
            let selector = NSSelectorFromString(argument)
            let controller = window?.windowController
            NSApp.sendAction(selector, to: controller?.responds(to: selector) == true ? controller : nil, from: nil)
        case "open":
            if let url = URL(string: argument) { NSApp.delegate?.application?(NSApp, open: [url]) }
        case "devpanel":
            let controller = window?.windowController as? BrowserWindowController
            if let section = DevPanelModel.Section.allCases.first(where: { $0.rawValue.lowercased() == argument }) {
                controller?.showDevPanel(section: section)
            }
        case "peek":
            let controller = window?.windowController as? BrowserWindowController
            if let url = URL(string: argument), let tab = controller?.tabs.selected { controller?.tab(tab, peek: url) }
        case "install-extension":
            Task { await ExtensionsHost.shared.installFromWebStore(argument) }
        case "js":
            let controller = window?.windowController as? BrowserWindowController
            guard let webView = controller?.tabs.focused?.webView else { return }
            Task {
                let log = Logger(subsystem: "com.joshoettinger.koala", category: "debug")
                do {
                    let result = try await webView.callAsyncJavaScript(argument, contentWorld: .page)
                    log.info("js \(String(describing: result), privacy: .public)")
                } catch {
                    log.info("js error \(error.localizedDescription, privacy: .public)")
                }
            }
        case "snapshot-settings":
            SettingsReview.saveSnapshot(suffix: argument)
        case "settings-search":
            SettingsReview.search(argument)
        case "settings-add-keyword":
            SettingsReview.addKeyword()
        case "suggest":
            (window?.windowController as? BrowserWindowController)?.reviewCommandBar(query: argument)
        case "suggest-address":
            (window?.windowController as? BrowserWindowController)?.reviewAddressField(query: argument)
        case "snapshot-suggestions":
            (window?.windowController as? BrowserWindowController)?.reviewSuggestionsSnapshot(name: argument)
        case "snapshot-window":
            // The chrome only: web content isn't drawn by cacheDisplay.
            if let view = window?.contentView { try? ReviewSnapshot.save(view, folder: "window", name: argument) }
        case "resize":
            let size = argument.split(separator: "x").compactMap { Double($0) }
            if size.count == 2 { window?.setContentSize(NSSize(width: size[0], height: size[1])) }
        default:
            break
        }
    }
}
#endif
