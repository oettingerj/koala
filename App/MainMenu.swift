import AppKit
import BrowserKit

/// The menu bar is the single source of truth for every command and its shortcut.
/// The command bar reads its commands from here.
@MainActor
enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(historyMenu()))
        main.addItem(submenu(developMenu()))
        main.addItem(submenu(githubMenu()))
        let bookmarks = NSMenu(title: "Bookmarks")
        bookmarks.delegate = BookmarksMenuDelegate.shared
        main.addItem(submenu(bookmarks))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = NSMenu(title: "Help")
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    static func item(_ title: String, _ action: Selector?, _ key: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.tag = tag
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Nano")
        menu.addItem(item("About Nano", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(AppDelegate.showSettings(_:)), ","))
        menu.addItem(.separator())
        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        NSApp.servicesMenu = services
        menu.addItem(servicesItem)
        menu.addItem(.separator())
        menu.addItem(item("Hide Nano", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit Nano", #selector(NSApplication.terminate(_:)), "q"))
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New Tab", #selector(BrowserWindowController.newTab(_:)), "t"))
        menu.addItem(item("New Blank Tab", #selector(BrowserWindowController.newBlankTab(_:)), "t", [.command, .option]))
        menu.addItem(item("New Window", #selector(AppDelegate.newWindow(_:)), "n"))
        menu.addItem(.separator())
        menu.addItem(item("Open Location…", #selector(BrowserWindowController.openLocation(_:)), "l"))
        menu.addItem(.separator())
        menu.addItem(item("Close Tab", #selector(BrowserWindowController.closeTab(_:)), "w"))
        menu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]))
        menu.addItem(item("Reopen Closed Tab", #selector(AppDelegate.reopenClosed(_:)), "t", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Copy URL", #selector(BrowserWindowController.copyURL(_:)), "c", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Import Bookmarks…", #selector(BrowserWindowController.importBookmarks(_:))))
        menu.addItem(item("Import Chrome History…", #selector(BrowserWindowController.importChromeHistory(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Print…", #selector(BrowserWindowController.printPage(_:)), "p"))
        menu.addItem(item("Copy Link as Markdown", #selector(BrowserWindowController.copyMarkdownLink(_:)), "c", [.command, .shift, .option]))
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", #selector(NSText.cut(_:)), "x"))
        menu.addItem(item("Copy", #selector(NSText.copy(_:)), "c"))
        menu.addItem(item("Paste", #selector(NSText.paste(_:)), "v"))
        menu.addItem(item("Paste and Match Style", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]))
        menu.addItem(item("Select All", #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(.separator())
        menu.addItem(item("Find…", #selector(BrowserWindowController.showFindBar(_:)), "f"))
        menu.addItem(item("Find Next", #selector(BrowserWindowController.findNext(_:)), "g"))
        menu.addItem(item("Find Previous", #selector(BrowserWindowController.findPrevious(_:)), "g", [.command, .shift]))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Reload Page", #selector(BrowserWindowController.reloadPage(_:)), "r"))
        menu.addItem(item("Reload from Origin", #selector(BrowserWindowController.hardReload(_:)), "r", [.command, .shift]))
        menu.addItem(item("Stop", #selector(BrowserWindowController.stopLoading(_:)), "."))
        menu.addItem(.separator())
        menu.addItem(item("Actual Size", #selector(BrowserWindowController.actualSize(_:)), "0"))
        menu.addItem(item("Zoom In", #selector(BrowserWindowController.zoomIn(_:)), "="))
        menu.addItem(item("Zoom Out", #selector(BrowserWindowController.zoomOut(_:)), "-"))
        menu.addItem(.separator())
        menu.addItem(item("Split with…", #selector(BrowserWindowController.splitWith(_:)), "\\"))
        menu.addItem(item("Separate Split View", #selector(BrowserWindowController.separateSplit(_:)), "\\", [.command, .shift]))
        menu.addItem(item("Close Split Pane", #selector(BrowserWindowController.closeSplitPane(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Show Bookmarks Bar", #selector(BrowserWindowController.toggleBookmarksBar(_:)), "b", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func developMenu() -> NSMenu {
        let menu = NSMenu(title: "Develop")
        menu.addItem(item("Show Dev Panel", #selector(BrowserWindowController.toggleDevPanel(_:)), "j", [.command, .option]))
        menu.addItem(item("View Source", #selector(BrowserWindowController.viewSource(_:)), "u", [.command, .option]))
        menu.addItem(item("Reload from Origin", #selector(BrowserWindowController.hardReload(_:)), "r", [.command, .shift]))
        menu.addItem(.separator())
        let note = NSMenuItem(title: "Web Inspector: right-click › Inspect Element", action: nil, keyEquivalent: "")
        note.isEnabled = false
        menu.addItem(note)
        return menu
    }

    private static func githubMenu() -> NSMenu {
        let menu = NSMenu(title: "GitHub")
        menu.addItem(item("Show Pull Request Details", #selector(BrowserWindowController.showGitHubContext(_:)), "g", [.command, .option]))
        menu.addItem(item("Review Queue", #selector(BrowserWindowController.showReviewQueue(_:)), "r", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Copy Permalink", #selector(BrowserWindowController.copyPermalink(_:)), "p", [.command, .option]))
        menu.addItem(item("Copy Checkout Command", #selector(BrowserWindowController.copyCheckoutCommand(_:))))
        menu.addItem(item("Open in Editor", #selector(BrowserWindowController.openInEditor(_:)), "e", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Sign In to GitHub…", #selector(BrowserWindowController.signInToGitHub(_:))))
        menu.addItem(item("Sign Out of GitHub", #selector(BrowserWindowController.signOutOfGitHub(_:))))
        return menu
    }

    private static func historyMenu() -> NSMenu {
        let menu = NSMenu(title: "History")
        menu.delegate = HistoryMenuDelegate.shared
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Show Next Tab", #selector(BrowserWindowController.selectNextTab(_:)), "]", [.command, .shift]))
        menu.addItem(item("Show Previous Tab", #selector(BrowserWindowController.selectPreviousTab(_:)), "[", [.command, .shift]))
        let nextAlt = item("Show Next Tab", #selector(BrowserWindowController.selectNextTab(_:)), "\t", .control)
        nextAlt.isHidden = true
        nextAlt.allowsKeyEquivalentWhenHidden = true
        menu.addItem(nextAlt)
        let previousAlt = item("Show Previous Tab", #selector(BrowserWindowController.selectPreviousTab(_:)), "\t", [.control, .shift])
        previousAlt.isHidden = true
        previousAlt.allowsKeyEquivalentWhenHidden = true
        menu.addItem(previousAlt)
        menu.addItem(item("Pin Tab", #selector(BrowserWindowController.togglePinTab(_:))))
        menu.addItem(item("Duplicate Tab", #selector(BrowserWindowController.duplicateTab(_:))))
        menu.addItem(.separator())
        for number in 1...9 {
            let title = number == 9 ? "Show Last Tab" : "Show Tab \(number)"
            menu.addItem(item(title, #selector(BrowserWindowController.selectTabByNumber(_:)), "\(number)", tag: number))
        }
        menu.addItem(.separator())
        menu.addItem(item("Downloads", #selector(BrowserWindowController.showDownloads(_:)), "l", [.command, .option]))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}

/// Rebuilds the History menu each time it opens: navigation, recently closed, and recent pages.
@MainActor
final class HistoryMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = HistoryMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        let recent = AppServices.shared.history.recentNow(limit: 15)
        menu.removeAllItems()
        menu.addItem(MainMenu.item("Back", #selector(BrowserWindowController.goBack(_:)), "["))
        menu.addItem(MainMenu.item("Forward", #selector(BrowserWindowController.goForward(_:)), "]"))
        menu.addItem(.separator())

        let closed = NSMenu(title: "Recently Closed")
        for (index, item) in AppServices.shared.recentlyClosed.enumerated().reversed() {
            let entry = NSMenuItem(title: item.title, action: #selector(AppDelegate.reopenClosedItem(_:)), keyEquivalent: "")
            entry.tag = index
            closed.addItem(entry)
        }
        let closedItem = NSMenuItem(title: "Recently Closed", action: nil, keyEquivalent: "")
        closedItem.submenu = closed
        closedItem.isEnabled = !AppServices.shared.recentlyClosed.isEmpty
        menu.addItem(closedItem)

        if !recent.isEmpty {
            menu.addItem(.separator())
            for entry in recent {
                guard let url = URL(string: entry.url) else { continue }
                let item = NSMenuItem(title: entry.title.isEmpty ? entry.url : entry.title,
                                      action: #selector(AppDelegate.openHistoryItem(_:)), keyEquivalent: "")
                item.representedObject = url
                item.toolTip = entry.url
                menu.addItem(item)
            }
        }
        menu.addItem(.separator())
        menu.addItem(MainMenu.item("Clear History…", #selector(AppDelegate.clearHistory(_:))))
    }
}

/// Rebuilds the Bookmarks menu from the library each time it opens.
@MainActor
final class BookmarksMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = BookmarksMenuDelegate()

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(MainMenu.item("Bookmark This Page", #selector(BrowserWindowController.toggleBookmark(_:)), "d"))
        menu.addItem(.separator())
        let library = AppServices.shared.bookmarks
        BookmarkMenus.append(library.children(of: nil), to: menu, library: library) { url, newTab in
            guard let controller = NSApp.keyWindow?.windowController as? BrowserWindowController else {
                NSApp.delegate?.application?(NSApp, open: [url])
                return
            }
            controller.openBookmark(url, newTab: newTab)
        }
    }
}
