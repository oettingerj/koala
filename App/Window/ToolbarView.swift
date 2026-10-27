import AppKit
import BrowserKit

/// Second chrome row: navigation, the address field, and page-level actions.
/// Shares the selected tab's surface so the two read as one piece.
final class ToolbarView: NSView {
    private let tabs: TabCollection
    let addressField = AddressField()

    private lazy var backButton = IconButton(symbol: "chevron.left", label: "Back", action: #selector(BrowserWindowController.goBack(_:)))
    private lazy var forwardButton = IconButton(symbol: "chevron.right", label: "Forward", action: #selector(BrowserWindowController.goForward(_:)))
    private lazy var reloadButton = IconButton(symbol: "arrow.clockwise", label: "Reload", action: #selector(BrowserWindowController.reloadOrStop(_:)))
    private lazy var devButton = IconButton(symbol: "chevron.left.forwardslash.chevron.right", label: "Dev Panel",
                                            pointSize: 12, action: #selector(BrowserWindowController.toggleDevPanel(_:)))
    private let errorBadge = NSTextField(labelWithString: "")
    private let hairline = CALayer()
    var showsHairline = true { didSet { hairline.isHidden = !showsHairline } }
    private let progressBar = CALayer()
    private var observation: ObservationLoop?
    private var lastProgressTabID: UUID?

    init(tabs: TabCollection) {
        self.tabs = tabs
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(hairline)
        layer?.addSublayer(progressBar)
        errorBadge.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        errorBadge.textColor = Theme.fail
        errorBadge.alignment = .left
        [backButton, forwardButton, reloadButton, addressField, devButton, errorBadge].forEach(addSubview)
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        observation = ObservationLoop { [weak self] in self?.sync() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = resolved(Theme.chromeSurface)
        hairline.backgroundColor = resolved(Theme.hairline)
        progressBar.backgroundColor = resolved(Theme.accent)
    }

    override func layout() {
        super.layout()
        let y = (bounds.height - Theme.iconButtonSize) / 2
        var x: CGFloat = 8
        for button in [backButton, forwardButton, reloadButton] {
            button.frame = NSRect(x: x, y: y, width: Theme.iconButtonSize, height: Theme.iconButtonSize)
            x += Theme.iconButtonSize + 2
        }
        x += 6
        let fieldHeight: CGFloat = 28
        let trailing = bounds.width - 8 - Theme.iconButtonSize
        devButton.frame = NSRect(x: trailing, y: y, width: Theme.iconButtonSize, height: Theme.iconButtonSize)
        errorBadge.sizeToFit()
        errorBadge.frame.origin = NSPoint(x: devButton.frame.maxX - 9, y: devButton.frame.maxY - 11)
        addressField.frame = NSRect(x: x, y: (bounds.height - fieldHeight) / 2, width: trailing - x - 8, height: fieldHeight)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hairline.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2))
        CATransaction.commit()
        layoutProgress(animated: false)
    }

    private func sync() {
        let tab = tabs.selected
        backButton.isEnabled = tab?.canGoBack ?? false
        forwardButton.isEnabled = tab?.canGoForward ?? false
        let loading = tab?.isLoading ?? false
        let symbol = loading ? "xmark" : "arrow.clockwise"
        reloadButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: loading ? "Stop" : "Reload")?
            .withSymbolConfiguration(.init(pointSize: loading ? 12 : 13, weight: .medium))
        reloadButton.toolTip = loading ? "Stop" : "Reload"
        addressField.show(tab?.url)
        // Error count for the page in view; the dev panel lists them.
        let errors = tab?.devTools.errorCount ?? 0
        errorBadge.stringValue = errors == 0 ? "" : errors > 99 ? "99+" : "\(errors)"
        devButton.toolTip = errors == 0 ? "Dev Panel (⌥⌘J)" : "Dev Panel (⌥⌘J) · \(errors) console error\(errors == 1 ? "" : "s")"
        needsLayout = true
        _ = tab?.progress
        let switchedTab = lastProgressTabID != tab?.id
        lastProgressTabID = tab?.id
        layoutProgress(animated: !switchedTab)
    }

    /// A 2pt accent line along the toolbar's bottom edge while the page loads.
    private func layoutProgress(animated: Bool) {
        let tab = tabs.selected
        let loading = tab?.isLoading ?? false
        let progress = loading ? max(0.08, tab?.progress ?? 0) : 0
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated && !Theme.reduceMotion ? 0.2 : 0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        progressBar.frame = NSRect(x: 0, y: 0, width: bounds.width * progress, height: 2)
        progressBar.opacity = loading ? 1 : 0
        CATransaction.commit()
    }
}
