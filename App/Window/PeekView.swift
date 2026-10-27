import AppKit
import BrowserKit
import WebKit

/// ⇧-click preview: the linked page floats over the current one. ⌘↩ makes it a tab, ⌘⇧↩
/// puts it in a split, Esc or a click outside dismisses it. Promoting keeps the same web
/// view, so the page never reloads.
final class PeekView: NSView {
    private let card = NSView()
    private let header = NSView()
    private let hostLabel = NSTextField(labelWithString: "")
    private lazy var splitButton = IconButton(symbol: "rectangle.split.2x1", label: "Open in Split (⇧⌘↩)", pointSize: 12,
                                              action: #selector(openInSplit), target: self)
    private lazy var tabButton = IconButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Open in Tab (⌘↩)", pointSize: 12,
                                            action: #selector(openInTab), target: self)
    private lazy var closeButton = IconButton(symbol: "xmark", label: "Close Peek (Esc)", pointSize: 11,
                                              action: #selector(close), target: self)
    private var webView: WKWebView?
    private var urlObservation: NSKeyValueObservation?
    private var keyMonitor: Any?

    var onOpenInTab: ((WKWebView) -> Void)?
    var onOpenInSplit: ((WKWebView) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        card.wantsLayer = true
        card.layer?.cornerRadius = Theme.panelRadius
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 1
        card.shadow = NSShadow()
        hostLabel.font = Theme.fieldMono
        hostLabel.textColor = Theme.textSecondary
        hostLabel.lineBreakMode = .byTruncatingMiddle
        header.wantsLayer = true
        [hostLabel, splitButton, tabButton, closeButton].forEach(header.addSubview)
        card.addSubview(header)
        addSubview(card)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Peek")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override var isFlipped: Bool { false }

    override func updateLayer() {
        layer?.backgroundColor = resolved(Theme.neutral(10)).copy(alpha: 0.18)
        card.layer?.backgroundColor = resolved(Theme.chromeSurface)
        card.layer?.borderColor = resolved(Theme.hairline)
        header.layer?.backgroundColor = resolved(Theme.chromeSurface)
    }

    func show(url: URL) {
        dismissWebView()
        let webView = WebViewFactory.makeWebView()
        card.addSubview(webView)
        self.webView = webView
        hostLabel.stringValue = DisplayURL(url).map { $0.host + $0.remainder } ?? url.absoluteString
        urlObservation = webView.observe(\.url) { [weak self] view, _ in
            MainActor.assumeIsolated {
                guard let url = view.url else { return }
                self?.hostLabel.stringValue = DisplayURL(url).map { $0.host + $0.remainder } ?? url.absoluteString
            }
        }
        webView.load(URLRequest(url: url))
        isHidden = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        animateIn()
        window?.makeFirstResponder(webView)
        installKeyMonitor()
    }

    private func animateIn() {
        guard !Theme.reduceMotion, let layer = card.layer else { return }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 0.97
        scale.toValue = 1
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0
        fade.toValue = 1
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = Theme.panelDuration
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(group, forKey: "peek")
    }

    override func layout() {
        super.layout()
        let insetX = max(24, bounds.width * 0.07)
        let insetY = max(16, bounds.height * 0.05)
        card.frame = bounds.insetBy(dx: insetX, dy: insetY)
        let headerHeight: CGFloat = 36
        header.frame = NSRect(x: 0, y: card.bounds.height - headerHeight, width: card.bounds.width, height: headerHeight)
        let y = (headerHeight - Theme.iconButtonSize) / 2
        closeButton.frame = NSRect(x: header.bounds.width - 6 - Theme.iconButtonSize, y: y, width: Theme.iconButtonSize, height: Theme.iconButtonSize)
        tabButton.frame = closeButton.frame.offsetBy(dx: -(Theme.iconButtonSize + 2), dy: 0)
        splitButton.frame = tabButton.frame.offsetBy(dx: -(Theme.iconButtonSize + 2), dy: 0)
        hostLabel.frame = NSRect(x: 14, y: (headerHeight - 16) / 2, width: splitButton.frame.minX - 24, height: 16)
        webView?.frame = NSRect(x: 0, y: 0, width: card.bounds.width, height: card.bounds.height - headerHeight - 1)
    }

    override func mouseDown(with event: NSEvent) {
        // A click on the dimmed backdrop, outside the card, dismisses.
        if !card.frame.contains(convert(event.locationInWindow, from: nil)) { close() }
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, !isHidden, event.window === window else { return event }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            switch (event.keyCode, flags) {
            case (53, []): close(); return nil
            case (36, .command): openInTab(); return nil
            case (36, [.command, .shift]): openInSplit(); return nil
            default: return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    @objc func close() {
        dismissWebView()
        hide()
    }

    @objc private func openInTab() {
        guard let webView = detach() else { return }
        hide()
        onOpenInTab?(webView)
    }

    @objc private func openInSplit() {
        guard let webView = detach() else { return }
        hide()
        onOpenInSplit?(webView)
    }

    private func detach() -> WKWebView? {
        urlObservation = nil
        let view = webView
        view?.removeFromSuperview()
        webView = nil
        return view
    }

    private func dismissWebView() {
        detach()?.stopLoading()
    }

    private func hide() {
        isHidden = true
        removeKeyMonitor()
    }
}
