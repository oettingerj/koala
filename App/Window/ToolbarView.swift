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
    let githubChip = GitHubChip()
    private(set) lazy var downloadsButton = IconButton(symbol: "arrow.down.circle", label: "Downloads", pointSize: 13,
                                                  action: #selector(BrowserWindowController.showDownloads(_:)))
    private let downloadsBadge = NSTextField(labelWithString: "")
    /// Pinned extensions; the rest are in the extensions menu.
    private(set) var extensionButtons: [ExtensionButton] = []
    private(set) lazy var extensionsMenuButton = IconButton(symbol: "ellipsis", label: "Extensions", pointSize: 13,
                                                       action: #selector(showExtensionsMenu(_:)), target: self)
    private(set) lazy var queueButton = IconButton(symbol: "tray", label: "Review Queue", pointSize: 12,
                                              action: #selector(BrowserWindowController.showReviewQueue(_:)))
    private let queueBadge = NSTextField(labelWithString: "")
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
        queueBadge.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        queueBadge.textColor = Theme.textSecondary
        githubChip.target = nil
        githubChip.action = #selector(BrowserWindowController.showGitHubContext(_:))
        githubChip.isHidden = true
        downloadsBadge.font = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
        downloadsBadge.textColor = Theme.accent
        downloadsButton.isHidden = true
        [backButton, forwardButton, reloadButton, addressField, githubChip, downloadsButton, downloadsBadge,
         extensionsMenuButton, queueButton, queueBadge, devButton].forEach(addSubview)
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
        var trailing = bounds.width - 8 - Theme.iconButtonSize
        devButton.frame = NSRect(x: trailing, y: y, width: Theme.iconButtonSize, height: Theme.iconButtonSize)
        trailing -= Theme.iconButtonSize + 2
        queueButton.frame = NSRect(x: trailing, y: y, width: Theme.iconButtonSize, height: Theme.iconButtonSize)
        queueBadge.sizeToFit()
        queueBadge.frame.origin = NSPoint(x: queueButton.frame.maxX - 9, y: queueButton.frame.maxY - 11)
        if !extensionsMenuButton.isHidden {
            trailing -= Theme.iconButtonSize + 2
            extensionsMenuButton.frame = NSRect(x: trailing, y: y, width: Theme.iconButtonSize, height: Theme.iconButtonSize)
        }
        for button in extensionButtons.reversed() {
            trailing -= Theme.iconButtonSize + 2
            button.frame = NSRect(x: trailing, y: y, width: Theme.iconButtonSize, height: Theme.iconButtonSize)
        }
        if !downloadsButton.isHidden {
            trailing -= Theme.iconButtonSize + 2
            downloadsButton.frame = NSRect(x: trailing, y: y, width: Theme.iconButtonSize, height: Theme.iconButtonSize)
            downloadsBadge.sizeToFit()
            downloadsBadge.frame.origin = NSPoint(x: downloadsButton.frame.maxX - 9, y: downloadsButton.frame.maxY - 11)
        }
        downloadsBadge.isHidden = downloadsButton.isHidden
        if !githubChip.isHidden {
            let width = min(githubChip.intrinsicContentSize.width, 280)
            trailing -= width + 6
            githubChip.frame = NSRect(x: trailing, y: (bounds.height - 24) / 2, width: width, height: 24)
        }
        addressField.frame = NSRect(x: x, y: (bounds.height - fieldHeight) / 2, width: trailing - x - 8, height: fieldHeight)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hairline.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2))
        CATransaction.commit()
        layoutProgress(animated: false)
    }

    private func syncExtensionButtons(for tab: Tab?) {
        let host = ExtensionsHost.shared
        _ = host.actionsVersion
        extensionsMenuButton.isHidden = host.contexts.isEmpty
        let ids = host.contexts.map(\.id).filter(host.isPinned)
        if extensionButtons.map(\.extensionID) != ids {
            extensionButtons.forEach { $0.removeFromSuperview() }
            extensionButtons = ids.map(ExtensionButton.init)
            extensionButtons.forEach { addSubview($0) }
        }
        extensionButtons.forEach { $0.update(for: tab) }
    }

    /// Every loaded extension's action, and which ones the toolbar shows.
    @objc private func showExtensionsMenu(_ sender: NSButton) {
        let host = ExtensionsHost.shared
        let menu = NSMenu()
        menu.autoenablesItems = false
        let pins = NSMenu()
        for (id, context) in host.contexts {
            let action = context.action(for: tabs.focused)
            let name = context.webExtension.displayName ?? "Extension"
            let item = closureMenuItem(name) { [weak self] in context.performAction(for: self?.tabs.focused) }
            if let icon = action?.icon(for: CGSize(width: 16, height: 16)) ?? context.webExtension.icon(for: CGSize(width: 16, height: 16)) {
                icon.size = NSSize(width: 16, height: 16)
                item.image = icon
            }
            item.isEnabled = action?.isEnabled ?? true
            menu.addItem(item)
            let pin = closureMenuItem(name) { host.setPinned(!host.isPinned(id), for: id) }
            pin.state = host.isPinned(id) ? .on : .off
            pins.addItem(pin)
        }
        menu.addItem(.separator())
        let pinItem = NSMenuItem(title: "Pin to Toolbar", action: nil, keyEquivalent: "")
        pinItem.submenu = pins
        menu.addItem(pinItem)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.isFlipped ? sender.bounds.maxY + 4 : -4), in: sender)
    }

    /// A brief pulse so a new download is noticed without a popup.
    func flashDownloads() {
        needsLayout = true
        layoutSubtreeIfNeeded()
        guard !Theme.reduceMotion, let layer = downloadsButton.layer else { return }
        let pulse = CABasicAnimation(keyPath: "transform.scale")
        pulse.fromValue = 1.25
        pulse.toValue = 1
        pulse.duration = 0.25
        pulse.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(pulse, forKey: "pulse")
    }

    private func sync() {
        let tab = tabs.focused
        backButton.isEnabled = tab?.canGoBack ?? false
        forwardButton.isEnabled = tab?.canGoForward ?? false
        let loading = tab?.isLoading ?? false
        let symbol = loading ? "xmark" : "arrow.clockwise"
        reloadButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: loading ? "Stop" : "Reload")?
            .withSymbolConfiguration(.init(pointSize: loading ? 12 : 13, weight: .medium))
        reloadButton.toolTip = loading ? "Stop" : "Reload"
        addressField.show(tab?.url)
        let github = GitHubURL(tab?.url)
        githubChip.isHidden = github == nil
        if let github { githubChip.show(github, status: GitHubService.shared.status(for: tab?.url)) }
        syncExtensionButtons(for: tab)
        let downloads = DownloadManager.shared
        downloadsButton.isHidden = downloads.items.isEmpty
        downloadsBadge.stringValue = downloads.activeCount == 0 ? "" : "\(downloads.activeCount)"
        let queued = GitHubService.shared.queue.count
        queueBadge.stringValue = queued == 0 ? "" : "\(queued)"
        queueButton.toolTip = queued == 0 ? "Review Queue" : "Review Queue · \(queued) waiting"
        // Console errors for the page in view, named in the tooltip only; the dev panel lists them.
        let errors = tab?.devTools.errorCount ?? 0
        devButton.toolTip = errors == 0 ? "Dev Panel (⌥⌘J)" : "Dev Panel (⌥⌘J) · \(errors) console error\(errors == 1 ? "" : "s")"
        needsLayout = true
        _ = tab?.progress
        let switchedTab = lastProgressTabID != tab?.id
        lastProgressTabID = tab?.id
        layoutProgress(animated: !switchedTab)
    }

    /// A 2pt accent line along the toolbar's bottom edge while the page loads.
    private func layoutProgress(animated: Bool) {
        let tab = tabs.focused
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
