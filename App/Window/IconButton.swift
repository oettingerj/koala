import AppKit

/// Borderless SF Symbol button with Nano's hover and pressed fills.
final class IconButton: NSButton {
    private var isHovered = false { didSet { updateFill() } }
    private var tracking: NSTrackingArea?

    init(symbol: String, label: String, pointSize: CGFloat = 13, action: Selector?, target: AnyObject? = nil) {
        super.init(frame: NSRect(x: 0, y: 0, width: Theme.iconButtonSize, height: Theme.iconButtonSize))
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .medium)
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?.withSymbolConfiguration(config)
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .regularSquare
        contentTintColor = Theme.textSecondary
        toolTip = label
        setAccessibilityLabel(label)
        self.action = action
        self.target = target
        wantsLayer = true
        layer?.cornerRadius = Theme.controlRadius
        layer?.cornerCurve = .continuous
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: Theme.iconButtonSize, height: Theme.iconButtonSize) }

    override var isEnabled: Bool { didSet { contentTintColor = isEnabled ? Theme.textSecondary : Theme.neutral(5) } }

    override var isHighlighted: Bool { didSet { updateFill() } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    private func updateFill() {
        let fill: NSColor? = !isEnabled ? nil : isHighlighted ? Theme.pressedFill : isHovered ? Theme.hoverFill : nil
        layer?.backgroundColor = fill.map(resolved) ?? .clear
    }
}
