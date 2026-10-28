import AppKit
import BrowserKit

@MainActor
protocol TabItemViewDelegate: AnyObject {
    func tabItemDidPress(_ item: TabItemView, event: NSEvent)
    func tabItemDidDrag(_ item: TabItemView, event: NSEvent)
    func tabItemDidEndDrag(_ item: TabItemView)
    func tabItemDidRequestClose(_ item: TabItemView)
    func tabItemMenu(_ item: TabItemView) -> NSMenu?
}

/// One tab in the strip. Selected tabs share the toolbar's surface and run down into it;
/// unselected tabs sit on the strip ground and only take a fill on hover.
final class TabItemView: NSView {
    let tab: Tab
    weak var delegate: TabItemViewDelegate?

    var isSelected = false { didSet { if isSelected != oldValue { needsDisplayUpdate() } } }
    /// Hide the trailing separator when a neighbor is selected or hovered.
    var showsSeparator = true { didSet { separator.isHidden = !showsSeparator } }
    private(set) var isHovered = false { didSet { if isHovered != oldValue { needsDisplayUpdate() } } }

    private let background = CALayer()
    /// CI result for GitHub pull request tabs, on the icon's corner.
    private let checksDot = CALayer()
    private let separator = CALayer()
    private let iconView = NSImageView()
    private let spinner = NSProgressIndicator()
    private let titleField = NSTextField(labelWithString: "")
    private lazy var closeButton = IconButton(symbol: "xmark", label: "Close Tab", pointSize: 9, action: #selector(closePressed), target: self)
    private var tracking: NSTrackingArea?
    private var observation: ObservationLoop?
    private var isDragging = false
    private var isPinned = false
    private var checks: GitHubStatus.Checks = .none

    static let pinnedWidth: CGFloat = 40

    /// Height of the visible tab body; the selected tab extends from the strip's bottom edge.
    static let bodyHeight: CGFloat = 32

    init(tab: Tab) {
        self.tab = tab
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = false

        background.cornerRadius = Theme.controlRadius
        background.cornerCurve = .continuous
        layer?.addSublayer(background)
        layer?.addSublayer(separator)
        checksDot.cornerRadius = 3.5
        checksDot.borderWidth = 1.5

        iconView.imageScaling = .scaleProportionallyDown
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        titleField.lineBreakMode = .byTruncatingTail
        titleField.cell?.truncatesLastVisibleLine = true
        titleField.maximumNumberOfLines = 1
        closeButton.layer?.cornerRadius = 4

        [iconView, spinner, titleField, closeButton].forEach(addSubview)
        layer?.addSublayer(checksDot)

        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)

        observation = ObservationLoop { [weak self] in self?.apply() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    deinit { MainActor.assumeIsolated { observation?.cancel() } }

    override var isFlipped: Bool { false }
    override var mouseDownCanMoveWindow: Bool { false }

    /// Icon and title are decoration: the tab takes their clicks, so a drag that starts on the
    /// title reorders tabs instead of moving the window (labels let the window move).
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        return hit.isDescendant(of: closeButton) ? hit : self
    }

    private func apply() {
        if isPinned != tab.isPinned {
            isPinned = tab.isPinned
            needsLayout = true
            superview?.needsLayout = true
        }
        // A split reads as one pill naming both pages.
        let title = tab.splitTab.map { "\(tab.displayTitle)  ⁄  \($0.displayTitle)" } ?? tab.displayTitle
        titleField.stringValue = title
        toolTip = title
        // GitHub pull requests and issues show their live state in place of the favicon.
        let status = GitHubService.shared.status(for: tab.url)
        iconView.image = status.flatMap { GitHubStyle.image($0.state) }
            ?? tab.favicon.map { FaviconContrast.displayImage($0, for: effectiveAppearance) } ?? Self.placeholderIcon
        iconView.contentTintColor = Theme.textSecondary
        checks = status?.checks ?? .none
        var label = title
        if let status { label += ", " + GitHubStyle.glyph(status.state).label.lowercased() }
        if let checks = GitHubStyle.label(checks) { label += ", " + checks }
        setAccessibilityLabel(label)
        updateColors()
        if tab.isLoading && tab.progress < 1 {
            spinner.startAnimation(nil)
            iconView.isHidden = true
        } else {
            spinner.stopAnimation(nil)
            iconView.isHidden = false
        }
    }

    private static let placeholderIcon: NSImage? = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)?
        .withSymbolConfiguration(.init(pointSize: 12, weight: .regular))

    // MARK: Layout

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let body = NSRect(x: 0, y: 0, width: bounds.width, height: Self.bodyHeight)
        if isSelected {
            background.frame = body
            background.maskedCorners = [.layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        } else {
            background.frame = body.insetBy(dx: 0, dy: 3).offsetBy(dx: 0, dy: 1)
            background.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        }
        separator.frame = NSRect(x: bounds.width + Theme.tabSpacing / 2 - 0.5, y: body.midY - 8, width: 1, height: 16)
        CATransaction.commit()

        let midY = body.midY
        let inset: CGFloat = 10
        if isPinned {
            iconView.frame = NSRect(x: (bounds.width - 16) / 2, y: midY - 8, width: 16, height: 16)
            spinner.frame = iconView.frame
            checksDot.frame = NSRect(x: iconView.frame.maxX - 5, y: iconView.frame.minY - 2, width: 7, height: 7)
            titleField.isHidden = true
            closeButton.isHidden = true
            return
        }
        titleField.isHidden = false
        iconView.frame = NSRect(x: inset, y: midY - 8, width: 16, height: 16)
        spinner.frame = iconView.frame
        checksDot.frame = NSRect(x: iconView.frame.maxX - 5, y: iconView.frame.minY - 2, width: 7, height: 7)
        let showsClose = isSelected || isHovered
        closeButton.isHidden = !showsClose
        closeButton.frame = NSRect(x: bounds.width - inset - 16 + 4, y: midY - 8, width: 16, height: 16)
        let titleX = iconView.frame.maxX + 8
        let titleEnd = showsClose ? closeButton.frame.minX - 4 : bounds.width - inset
        titleField.frame = NSRect(x: titleX, y: midY - 8, width: max(0, titleEnd - titleX), height: 16)
    }

    private func needsDisplayUpdate() {
        titleField.font = isSelected ? Theme.tabTitleSelected : Theme.tabTitle
        titleField.textColor = isSelected ? Theme.textPrimary : Theme.textSecondary
        setAccessibilityValue(isSelected)
        updateColors()
        needsLayout = true
    }

    private func updateColors() {
        CATransaction.begin()
        CATransaction.setAnimationDuration(Theme.reduceMotion ? 0 : Theme.hoverDuration)
        background.backgroundColor = isSelected ? resolved(Theme.chromeSurface)
            : isHovered ? resolved(Theme.hoverFill) : .clear
        separator.backgroundColor = resolved(Theme.hairline)
        checksDot.isHidden = checks == .none
        checksDot.backgroundColor = GitHubStyle.color(checks).map(resolved)
        checksDot.borderColor = resolved(isSelected ? Theme.chromeSurface : isHovered ? Theme.hoverFill : Theme.stripGround)
        // An unselected tab shows its close button only on hover, over the hover fill. The ramp's
        // next steps read too heavy there, so the button tints that fill with text-primary instead.
        closeButton.hoverFill = isSelected ? Theme.hoverFill : Theme.textPrimary.withAlphaComponent(0.1)
        closeButton.pressedFill = isSelected ? Theme.pressedFill : Theme.textPrimary.withAlphaComponent(0.16)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        apply()
        updateColors()
    }

    // MARK: Events

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true; superview?.needsLayout = true }
    override func mouseExited(with event: NSEvent) { isHovered = false; superview?.needsLayout = true }

    override func mouseDown(with event: NSEvent) {
        isDragging = false
        delegate?.tabItemDidPress(self, event: event)
    }

    override func mouseDragged(with event: NSEvent) {
        isDragging = true
        delegate?.tabItemDidDrag(self, event: event)
    }

    override func mouseUp(with event: NSEvent) {
        isDragging = false
        delegate?.tabItemDidEndDrag(self)
    }

    override func otherMouseUp(with event: NSEvent) {
        if event.buttonNumber == 2 { delegate?.tabItemDidRequestClose(self) }
    }

    @objc private func closePressed() { delegate?.tabItemDidRequestClose(self) }

    override func menu(for event: NSEvent) -> NSMenu? { delegate?.tabItemMenu(self) }

    override func accessibilityPerformPress() -> Bool {
        guard let event = NSApp.currentEvent else { return false }
        delegate?.tabItemDidPress(self, event: event)
        return true
    }
}
