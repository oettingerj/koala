import AppKit
import BrowserKit

/// Toolbar chip naming the repository (and PR or issue) on any GitHub page, with a checks dot.
final class GitHubChip: NSButton {
    private let dot = CALayer()
    private var isHovered = false { didSet { updateFill() } }
    private var tracking: NSTrackingArea?
    private var checks: GitHubStatus.Checks = .none

    override init(frame: NSRect) {
        super.init(frame: frame)
        isBordered = false
        bezelStyle = .regularSquare
        wantsLayer = true
        layer?.cornerRadius = Theme.controlRadius
        layer?.cornerCurve = .continuous
        layer?.addSublayer(dot)
        dot.cornerRadius = 3.5
        imagePosition = .imageLeading
        imageHugsTitle = true
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show(_ github: GitHubURL, status: GitHubStatus?) {
        checks = status?.checks ?? .none
        image = status.flatMap { GitHubStyle.image($0.state, size: 11) }
        attributedTitle = NSAttributedString(string: (image == nil ? "" : " ") + github.label, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: Theme.textSecondary,
        ])
        var description = github.label
        if let status { description += ", " + GitHubStyle.glyph(status.state).label.lowercased() }
        if let checks = GitHubStyle.label(checks) { description += ", " + checks }
        setAccessibilityLabel(description)
        toolTip = status?.title ?? github.slug
        updateFill()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.width += checks == .none ? 16 : 26
        size.height = 24
        return size
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dot.isHidden = checks == .none
        dot.frame = NSRect(x: bounds.width - 15, y: bounds.midY - 3.5, width: 7, height: 7)
        CATransaction.commit()
    }

    override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: Theme.controlRadius, yRadius: Theme.controlRadius).fill() }
    override var focusRingMaskBounds: NSRect { bounds }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override var isHighlighted: Bool { didSet { updateFill() } }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    private func updateFill() {
        layer?.backgroundColor = resolved(isHighlighted ? Theme.pressedFill : isHovered ? Theme.hoverFill : Theme.fieldFill)
        dot.backgroundColor = GitHubStyle.color(checks).map(resolved)
    }
}
