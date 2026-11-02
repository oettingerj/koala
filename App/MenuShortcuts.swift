import AppKit
import BrowserKit

/// The user's shortcut overrides for menu commands. Every command made through `MainMenu.item`
/// registers here with its built-in shortcut; the menu bar stays the single source of truth for
/// what each key does, and Settings and the command bar read it back from there.
@MainActor
enum MenuShortcuts {
    /// One rebindable command, as Settings lists it.
    struct Command: Identifiable, Equatable {
        let id: String
        /// The title the command was built with, before any Show/Hide toggling.
        let title: String
        /// The menu bar menu it lives in, such as "File".
        let menu: String
        let defaultShortcut: MenuShortcut
        let shortcut: MenuShortcut

        var isCustomized: Bool { shortcut != defaultShortcut }
    }

    private static var defaults: [String: (title: String, shortcut: MenuShortcut)] = [:]

    /// The selector, plus the tag for commands that share one (Show Tab 1–9, dev sections).
    static func id(for item: NSMenuItem) -> String? {
        guard let action = item.action else { return nil }
        let selector = NSStringFromSelector(action)
        return item.tag == 0 ? selector : "\(selector)#\(item.tag)"
    }

    static func shortcut(of item: NSMenuItem) -> MenuShortcut {
        MenuShortcut(key: item.keyEquivalent, modifiers: item.keyEquivalentModifierMask)
    }

    /// Records the item's built-in shortcut the first time its command is seen, then gives it the user's.
    static func register(_ item: NSMenuItem) {
        guard let id = id(for: item) else { return }
        if defaults[id] == nil { defaults[id] = (item.title, shortcut(of: item)) }
        apply(current(for: id), to: item)
    }

    /// The shortcut a command has now: the user's override, else its built-in one.
    static func current(for id: String) -> MenuShortcut {
        Preferences.menuShortcuts[id] ?? defaults[id]?.shortcut ?? .none
    }

    /// Sets a command's shortcut; nil goes back to its built-in one.
    static func set(_ shortcut: MenuShortcut?, for id: String) {
        var overrides = Preferences.menuShortcuts
        overrides[id] = shortcut == defaults[id]?.shortcut ? nil : shortcut
        Preferences.menuShortcuts = overrides
        applyAll()
    }

    static func resetAll() {
        Preferences.menuShortcuts = [:]
        applyAll()
    }

    /// Gives every registered menu item its current shortcut. Hidden alternates are never registered.
    private static func applyAll() {
        walk { item, _ in
            if let id = id(for: item), defaults[id] != nil, !item.isHidden { apply(current(for: id), to: item) }
        }
    }

    private static func apply(_ shortcut: MenuShortcut, to item: NSMenuItem) {
        item.keyEquivalent = shortcut.key
        item.keyEquivalentModifierMask = shortcut.isNone ? [] : shortcut.modifierFlags
    }

    /// Every registered command in menu bar order.
    static func commands() -> [Command] {
        var seen: Set<String> = []
        var commands: [Command] = []
        walk(populating: true) { item, menu in
            guard !item.isHidden, let id = id(for: item), let base = defaults[id], seen.insert(id).inserted else { return }
            commands.append(Command(id: id, title: base.title, menu: menu, defaultShortcut: base.shortcut, shortcut: current(for: id)))
        }
        return commands
    }

    /// The title of the menu item that already answers to `shortcut`, other than command `id`.
    static func owner(of shortcut: MenuShortcut, excluding id: String) -> String? {
        guard !shortcut.isNone else { return nil }
        var owner: String?
        walk(populating: true) { item, _ in
            guard owner == nil, Self.id(for: item) != id, Self.shortcut(of: item) == shortcut else { return }
            owner = Self.id(for: item).flatMap { defaults[$0]?.title } ?? item.title
        }
        return owner
    }

    /// A command's shortcut for hint text, such as "⌥⌘J"; nil when it has none.
    static func text(for action: Selector) -> String? {
        let shortcut = current(for: NSStringFromSelector(action))
        return shortcut.isNone ? nil : shortcut.display
    }

    /// `title (⌘D)`, or the bare title when the command has no shortcut.
    static func label(_ title: String, for action: Selector) -> String {
        text(for: action).map { "\(title) (\($0))" } ?? title
    }

    /// Visits every item under the menu bar with the name of its top-level menu. `populating`
    /// builds delegate menus (History, Bookmarks) first, since they fill in only when opened.
    private static func walk(populating: Bool = false, _ visit: (NSMenuItem, String) -> Void) {
        guard let main = NSApp.mainMenu else { return }
        func descend(_ menu: NSMenu, top: String) {
            // Only Koala's own dynamic menus: AppKit's delegates (Help's search) must not be driven by hand.
            if populating, let delegate = menu.delegate, delegate is HistoryMenuDelegate || delegate is BookmarksMenuDelegate {
                delegate.menuNeedsUpdate?(menu)
            }
            for item in menu.items where !item.isSeparatorItem {
                if let submenu = item.submenu {
                    // Services lists other apps' commands, not Koala's.
                    guard submenu !== NSApp.servicesMenu else { continue }
                    descend(submenu, top: menu === main ? submenu.title : top)
                } else if menu !== main {
                    visit(item, top)
                }
            }
        }
        descend(main, top: "")
    }
}
