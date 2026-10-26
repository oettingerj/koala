import AppKit
import BrowserKit

/// The titlebar row: traffic lights, tabs, and the new-tab button.
/// Lays tabs out by frame (no Auto Layout per tab) so a hundred tabs relayout in one pass.
final class TabStripView: NSView {
    private let tabs: TabCollection
    private var items: [UUID: TabItemView] = [:]
    private var order: [TabItemView] = []
    private var observation: ObservationLoop?

    private lazy var newTabButton = IconButton(symbol: "plus", label: "New Tab", action: #selector(BrowserWindowController.newTab(_:)))
    private let leadingGuide = NSTextField(labelWithString: "")
    private let trailingGuide = NSTextField(labelWithString: "")

    /// Horizontal scroll offset when tabs overflow at minimum width.
    private var scrollOffset: CGFloat = 0
    private var drag: (item: TabItemView, grabOffset: CGFloat)?

    var leadingInset = Theme.trafficLightInset { didSet { needsLayout = true } }

    var onSelect: ((Tab) -> Void)?
    var onClose: ((Tab) -> Void)?

    init(tabs: TabCollection) {
        self.tabs = tabs
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(newTabButton)
        for guide in [leadingGuide, trailingGuide] {
            guide.font = .systemFont(ofSize: 11)
            guide.textColor = Theme.textTertiary
            guide.lineBreakMode = .byTruncatingTail
            guide.isHidden = true
            guide.drawsBackground = true
            guide.backgroundColor = Theme.stripGround
            addSubview(guide)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.tabGroup)
        setAccessibilityLabel("Tabs")
        observation = ObservationLoop { [weak self] in self?.sync() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = resolved(Theme.stripGround)
    }
    override var wantsUpdateLayer: Bool { true }

    // MARK: Model sync

    private func sync() {
        let current = tabs.tabs
        let selectedID = tabs.selectedID
        let ids = Set(current.map(\.id))

        for (id, item) in items where !ids.contains(id) {
            item.removeFromSuperview()
            items[id] = nil
        }
        order = current.map { tab in
            if let item = items[tab.id] { return item }
            let item = TabItemView(tab: tab)
            item.delegate = self
            addSubview(item, positioned: .below, relativeTo: newTabButton)
            items[tab.id] = item
            return item
        }
        for item in order { item.isSelected = item.tab.id == selectedID }
        setAccessibilityChildren(order)
        needsLayout = true
        scrollSelectedIntoView()
    }

    // MARK: Layout

    private var tabsArea: NSRect {
        let leading = leadingInset
        let trailing = bounds.width - Theme.iconButtonSize - 12
        return NSRect(x: leading, y: 0, width: max(0, trailing - leading), height: bounds.height)
    }

    private var tabWidth: CGFloat {
        guard !order.isEmpty else { return Theme.tabMaxWidth }
        let fit = (tabsArea.width - Theme.tabSpacing * CGFloat(order.count - 1)) / CGFloat(order.count)
        return min(Theme.tabMaxWidth, max(Theme.tabMinWidth, fit.rounded(.down)))
    }

    private var contentWidth: CGFloat {
        CGFloat(order.count) * tabWidth + Theme.tabSpacing * CGFloat(max(0, order.count - 1))
    }

    private var maxScroll: CGFloat { max(0, contentWidth - tabsArea.width) }

    override func layout() {
        super.layout()
        scrollOffset = min(max(0, scrollOffset), maxScroll)
        let area = tabsArea
        let width = tabWidth
        let selectedIndex = order.firstIndex { $0.isSelected }
        let hoveredIndex = order.firstIndex { $0.isHovered }

        for (index, item) in order.enumerated() {
            var x = area.minX + CGFloat(index) * (width + Theme.tabSpacing) - scrollOffset
            if let drag, drag.item === item, let window {
                let mouseX = convert(window.mouseLocationOutsideOfEventStream, from: nil).x
                x = min(max(area.minX, mouseX - drag.grabOffset), area.maxX - width)
            }
            item.frame = NSRect(x: x.rounded(), y: 0, width: width, height: TabItemView.bodyHeight)
            let next = index + 1
            item.showsSeparator = index != selectedIndex && next != selectedIndex
                && index != hoveredIndex && next != hoveredIndex && next < order.count
        }

        let lastMaxX = order.last.map { $0.frame.maxX } ?? area.minX
        let buttonX = min(lastMaxX + 6, bounds.width - Theme.iconButtonSize - 8)
        newTabButton.frame = NSRect(x: buttonX, y: (TabItemView.bodyHeight - Theme.iconButtonSize) / 2 + 1,
                                    width: Theme.iconButtonSize, height: Theme.iconButtonSize)
        let visible = layoutGuideWords(area: area)
        clipTabs(to: visible)
    }

    private static let guideWidth: CGFloat = 132

    /// Guide words: when tabs overflow, each edge names how many tabs are hidden past it and
    /// the nearest one's title, instead of crushing every tab to an icon. Returns the area
    /// left for tabs once the guides take their edges.
    private func layoutGuideWords(area: NSRect) -> NSRect {
        var visible = area
        if order.contains(where: { $0.frame.minX < area.minX - 1 }) {
            visible.origin.x += Self.guideWidth
            visible.size.width -= Self.guideWidth
        }
        if order.contains(where: { $0.frame.maxX > area.maxX + 1 }) {
            visible.size.width -= Self.guideWidth
        }
        let hiddenLeading = order.filter { $0.frame.midX < visible.minX }
        let hiddenTrailing = order.filter { $0.frame.midX > visible.maxX }
        let y = TabItemView.bodyHeight / 2 - 7
        configureGuide(leadingGuide, hidden: hiddenLeading.reversed(), alignment: .left,
                       frame: NSRect(x: area.minX + 4, y: y, width: Self.guideWidth - 12, height: 14))
        configureGuide(trailingGuide, hidden: hiddenTrailing, alignment: .right,
                       frame: NSRect(x: area.maxX - Self.guideWidth + 8, y: y, width: Self.guideWidth - 12, height: 14))
        return visible
    }

    private func configureGuide(_ guide: NSTextField, hidden: [TabItemView], alignment: NSTextAlignment, frame: NSRect) {
        guard let nearest = hidden.first else { guide.isHidden = true; return }
        guide.isHidden = false
        guide.alignment = alignment
        let arrow = alignment == .left ? "‹" : "›"
        let text = hidden.count == 1 ? nearest.tab.displayTitle : "\(hidden.count) · \(nearest.tab.displayTitle)"
        guide.stringValue = alignment == .left ? "\(arrow) \(text)" : "\(text) \(arrow)"
        guide.toolTip = "\(hidden.count) more tabs"
        guide.frame = frame
    }

    /// Tabs cut by an edge are hidden rather than clipped, so the strip never shows a sliver.
    /// The dragged tab is exempt so it can be pulled past the edge to scroll.
    private func clipTabs(to area: NSRect) {
        for item in order where drag?.item !== item {
            item.isHidden = item.frame.minX < area.minX - 1 || item.frame.maxX > area.maxX + 1
        }
    }

    private func scrollSelectedIntoView() {
        guard let index = order.firstIndex(where: \.isSelected) else { return }
        let width = tabWidth
        let start = CGFloat(index) * (width + Theme.tabSpacing)
        let edgeReserve = maxScroll > 0 ? Self.guideWidth : 0
        if start - edgeReserve < scrollOffset {
            scrollOffset = start - edgeReserve
        } else if start + width + edgeReserve > scrollOffset + tabsArea.width {
            scrollOffset = start + width + edgeReserve - tabsArea.width
        }
    }

    override func scrollWheel(with event: NSEvent) {
        guard maxScroll > 0 else { return super.scrollWheel(with: event) }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        scrollOffset -= delta * (event.hasPreciseScrollingDeltas ? 1 : 8)
        needsLayout = true
    }

    // MARK: Window behaviors

    override func mouseUp(with event: NSEvent) {
        guard event.clickCount == 2 else { return super.mouseUp(with: event) }
        let action = UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") ?? "Maximize"
        switch action {
        case "Minimize": window?.performMiniaturize(nil)
        case "None": break
        default: window?.performZoom(nil)
        }
    }
}

extension TabStripView: TabItemViewDelegate {
    func tabItemDidPress(_ item: TabItemView, event: NSEvent) {
        let grab = convert(event.locationInWindow, from: nil).x - item.frame.minX
        drag = (item, grab)
        onSelect?(item.tab)
    }

    func tabItemDidDrag(_ item: TabItemView, event: NSEvent) {
        guard let drag, drag.item === item, let from = order.firstIndex(where: { $0 === item }) else { return }
        let area = tabsArea
        let mouseX = convert(event.locationInWindow, from: nil).x
        let center = mouseX - drag.grabOffset + tabWidth / 2 + scrollOffset - area.minX
        let target = min(max(0, Int(center / (tabWidth + Theme.tabSpacing))), order.count - 1)
        item.layer?.zPosition = 1
        if target != from {
            tabs.move(item.tab, to: target)
        } else {
            needsLayout = true
        }
    }

    func tabItemDidEndDrag(_ item: TabItemView) {
        item.layer?.zPosition = 0
        drag = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.reduceMotion ? 0 : Theme.panelDuration
            context.allowsImplicitAnimation = true
            layoutSubtreeIfNeeded()
            needsLayout = true
        }
    }

    func tabItemDidRequestClose(_ item: TabItemView) {
        drag = nil
        onClose?(item.tab)
    }
}
