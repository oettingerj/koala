import AppKit

/// A menu item that runs a closure, for menus built on the fly (tab and bookmark context menus).
func closureMenuItem(_ title: String, handler: @escaping @MainActor () -> Void) -> NSMenuItem {
    let target = ClosureTarget(handler)
    let item = NSMenuItem(title: title, action: #selector(ClosureTarget.run), keyEquivalent: "")
    item.target = target
    item.representedObject = target // menu items hold their target weakly
    return item
}

private final class ClosureTarget: NSObject {
    private let handler: @MainActor () -> Void

    init(_ handler: @escaping @MainActor () -> Void) {
        self.handler = handler
    }

    @objc func run() { handler() }
}
