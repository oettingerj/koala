import AppKit
import BrowserKit
import WebKit

/// One extension's toolbar action: its icon, badge, and click.
final class ExtensionButton: IconButton {
    let extensionID: String
    private let badge = NSTextField(labelWithString: "")

    init(extensionID: String) {
        self.extensionID = extensionID
        super.init(symbol: "puzzlepiece.extension", label: "Extension", pointSize: 12, action: #selector(pressed), target: nil)
        target = self
        badge.font = .monospacedDigitSystemFont(ofSize: 8, weight: .bold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 5
        badge.isHidden = true
        addSubview(badge)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private var context: WKWebExtensionContext? {
        ExtensionsHost.shared.contexts.first { $0.id == extensionID }?.context
    }

    func update(for tab: Tab?) {
        guard let context else { return }
        let action = context.action(for: tab)
        let name = context.webExtension.displayName ?? "Extension"
        if let icon = action?.icon(for: CGSize(width: 16, height: 16)) ?? context.webExtension.icon(for: CGSize(width: 16, height: 16)) {
            icon.size = NSSize(width: 16, height: 16)
            image = icon
        }
        let label = action?.label.isEmpty == false ? action!.label : name
        toolTip = label
        setAccessibilityLabel(label)
        isEnabled = action?.isEnabled ?? true
        let text = action?.badgeText ?? ""
        badge.isHidden = text.isEmpty
        badge.stringValue = text
        badge.layer?.backgroundColor = resolved(Theme.fail)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        badge.sizeToFit()
        let width = max(10, badge.frame.width + 4)
        badge.frame = NSRect(x: bounds.width - width, y: bounds.height - 11, width: width, height: 10)
    }

    @objc private func pressed() {
        guard let context, let controller = window?.windowController as? BrowserWindowController else { return }
        context.performAction(for: controller.tabs.focused)
    }
}
