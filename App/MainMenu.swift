import AppKit

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

    private static func item(_ title: String, _ action: Selector?, _ key: String = "",
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
        menu.addItem(item("New Window", #selector(AppDelegate.newWindow(_:)), "n"))
        menu.addItem(.separator())
        menu.addItem(item("Open Location…", #selector(BrowserWindowController.openLocation(_:)), "l"))
        menu.addItem(.separator())
        menu.addItem(item("Close Tab", #selector(BrowserWindowController.closeTab(_:)), "w"))
        menu.addItem(item("Close Window", #selector(NSWindow.performClose(_:)), "w", [.command, .shift]))
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
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control]))
        return menu
    }

    private static func historyMenu() -> NSMenu {
        let menu = NSMenu(title: "History")
        menu.addItem(item("Back", #selector(BrowserWindowController.goBack(_:)), "["))
        menu.addItem(item("Forward", #selector(BrowserWindowController.goForward(_:)), "]"))
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
        menu.addItem(.separator())
        for number in 1...9 {
            let title = number == 9 ? "Show Last Tab" : "Show Tab \(number)"
            menu.addItem(item(title, #selector(BrowserWindowController.selectTabByNumber(_:)), "\(number)", tag: number))
        }
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return menu
    }
}
