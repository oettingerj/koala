import AppKit
import BrowserKit
import SwiftUI

/// ⌘T: a floating bar over the page that opens URLs, searches, switches tabs, and runs any
/// menu command. Built once per window and kept hidden so opening it costs one order-front.
@MainActor
final class CommandBar: NSObject, NSWindowDelegate, NSTextFieldDelegate {
    let model: SuggestionModel
    private let panel: CommandBarPanel
    private let container = CommandBarContainer()
    private let field = NSTextField()
    private let searchIcon = NSImageView()
    private let divider = NSView()
    private let list: NSHostingView<SuggestionList>
    private weak var parent: NSWindow?
    private var heightObservation: ObservationLoop?

    var onActivate: ((Suggestion, _ newTab: Bool) -> Void)?
    var onCancel: (() -> Void)?
    private static let defaultPlaceholder = "Search, open a URL, or run a command"

    static let width: CGFloat = 640
    private static let fieldHeight: CGFloat = 52
    private static let rowHeight: CGFloat = 40

    init(engine: SuggestionEngine) {
        model = SuggestionModel(engine: engine)
        panel = CommandBarPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.fieldHeight),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        list = NSHostingView(rootView: SuggestionList(model: model, onActivate: { _ in }))
        super.init()
        list.rootView = SuggestionList(model: model) { [weak self] row in self?.activate(row, newTab: false) }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.delegate = self

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 16)
        field.textColor = Theme.textPrimary
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderAttributedString = NSAttributedString(string: "Search, open a URL, or run a command", attributes: [
            .font: NSFont.systemFont(ofSize: 16), .foregroundColor: Theme.textTertiary,
        ])
        field.delegate = self
        field.setAccessibilityLabel("Command bar")
        searchIcon.image = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
        searchIcon.contentTintColor = Theme.textTertiary
        divider.wantsLayer = true

        [searchIcon, field, divider, list].forEach(container.addSubview)
        container.layoutHandler = { [weak self] in self?.layoutContents() }
        panel.contentView = container
        heightObservation = ObservationLoop { [weak self] in self?.resize() }
    }

    var isVisible: Bool { panel.isVisible }

    /// Distance from the window's top edge to the top of the page, so the bar floats just
    /// below the chrome rather than over it.
    private var chromeHeight: CGFloat = 104

    func show(over window: NSWindow, chromeHeight: CGFloat, placeholder: String = CommandBar.defaultPlaceholder) {
        parent = window
        self.chromeHeight = chromeHeight
        field.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .font: NSFont.systemFont(ofSize: 16), .foregroundColor: Theme.textTertiary,
        ])
        model.reset()
        field.stringValue = ""
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        Perf.measure("commandbar.open") {
            resize()
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(field)
        }
    }

    func hide() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        parent?.makeKey()
    }

    private func cancel() {
        hide()
        onCancel?()
    }

    private func activate(_ row: Suggestion, newTab: Bool) {
        hide()
        onActivate?(row, newTab)
    }

    private func resize() {
        let rows = model.rows.count
        let height = Self.fieldHeight + (rows == 0 ? 0 : CGFloat(rows) * Self.rowHeight + 13)
        guard let parent else { return }
        let width = min(Self.width, parent.frame.width - 48)
        let top = parent.frame.maxY - chromeHeight - 12
        let x = parent.frame.midX - width / 2
        panel.setFrame(NSRect(x: x.rounded(), y: (top - height).rounded(), width: width, height: height), display: true)
    }

    private func layoutContents() {
        let bounds = container.bounds
        let fieldTop = bounds.height - Self.fieldHeight
        searchIcon.frame = NSRect(x: 16, y: fieldTop + (Self.fieldHeight - 18) / 2, width: 18, height: 18)
        field.frame = NSRect(x: 44, y: fieldTop + (Self.fieldHeight - 22) / 2, width: bounds.width - 60, height: 22)
        divider.isHidden = model.rows.isEmpty
        divider.frame = NSRect(x: 0, y: fieldTop - 1, width: bounds.width, height: 1)
        divider.layer?.backgroundColor = container.resolved(Theme.hairline)
        list.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, fieldTop - 1))
    }

    // MARK: Field

    func controlTextDidChange(_ obj: Notification) {
        model.update(query: field.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        // ⌃N / ⌃P arrive here as moveDown / moveUp through the standard key bindings.
        case #selector(NSResponder.moveUp(_:)):
            model.moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)):
            model.moveSelection(by: 1)
        case #selector(NSResponder.insertNewline(_:)):
            if let row = model.selected {
                activate(row, newTab: NSApp.currentEvent?.modifierFlags.contains(.command) ?? false)
            }
        case #selector(NSResponder.cancelOperation(_:)):
            cancel()
        default:
            return false
        }
        return true
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking anywhere else dismisses the bar, like a menu.
        if panel.isVisible {
            panel.orderOut(nil)
            onCancel?()
        }
    }
}

final class CommandBarPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The bar's rounded, bordered surface.
final class CommandBarContainer: NSView {
    var layoutHandler: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Theme.panelRadius
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        layer?.borderWidth = 1
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = resolved(Theme.chromeSurface)
        layer?.borderColor = resolved(Theme.hairline)
    }

    override func layout() {
        super.layout()
        layoutHandler?()
    }
}

/// Collects every enabled menu bar command for the command bar.
@MainActor
enum MenuCommands {
    private static let excluded: Set<String> = [
        "openHistoryItem:", "reopenClosedItem:", "run", "newTab:", "openLocation:", "submenuAction:",
    ]

    static func collect() -> [SuggestionEngine.CommandInfo] {
        guard let main = NSApp.mainMenu else { return [] }
        var commands: [SuggestionEngine.CommandInfo] = []
        func walk(_ menu: NSMenu) {
            menu.update()
            for item in menu.items where !item.isSeparatorItem && !item.isHidden {
                if let submenu = item.submenu {
                    // Dynamic menus (History, Bookmarks) list pages, not commands; skip their entries.
                    if menu === main && submenu.delegate != nil {
                        for entry in submenu.items where entry.action != nil { append(entry, to: &commands) }
                    } else if menu !== main || item.title != "Services" {
                        walk(submenu)
                    }
                } else {
                    append(item, to: &commands)
                }
            }
        }
        walk(main)
        return commands
    }

    private static func append(_ item: NSMenuItem, to commands: inout [SuggestionEngine.CommandInfo]) {
        guard let action = item.action, item.isEnabled, !item.title.isEmpty else { return }
        let selector = NSStringFromSelector(action)
        guard !excluded.contains(selector), item.title != "Services" else { return }
        if commands.contains(where: { $0.title == item.title }) { return }
        commands.append(.init(selector: selector, title: item.title, shortcut: shortcut(for: item)))
    }

    static func shortcut(for item: NSMenuItem) -> String? {
        guard !item.keyEquivalent.isEmpty else { return nil }
        let flags = item.keyEquivalentModifierMask
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        let key: String = switch item.keyEquivalent {
        case "\t": "⇥"
        case "\r": "↩"
        case " ": "Space"
        default: item.keyEquivalent.uppercased()
        }
        return text + key
    }
}
