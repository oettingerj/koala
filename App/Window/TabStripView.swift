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
    private let leadingGuide = GuideButton(edge: .leading)
    private let trailingGuide = GuideButton(edge: .trailing)

    /// Horizontal scroll offset when tabs overflow at minimum width.
    private var scrollOffset: CGFloat = 0
    private var drag: (item: TabItemView, grabOffset: CGFloat)?

    var leadingInset = Theme.trafficLightInset { didSet { needsLayout = true } }

    var onSelect: ((Tab) -> Void)?
    var onClose: ((Tab) -> Void)?
    var menuForTab: ((Tab) -> NSMenu?)?

    init(tabs: TabCollection) {
        self.tabs = tabs
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(newTabButton)
        for guide in [leadingGuide, trailingGuide] {
            guide.isHidden = true
            guide.target = self
            guide.action = #selector(revealGuidedTab(_:))
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

    private var pinnedCount: Int { order.prefix { $0.tab.isPinned }.count }

    /// Width of the pinned group plus its trailing gap; pinned tabs never scroll.
    private var pinnedWidth: CGFloat {
        pinnedCount == 0 ? 0 : CGFloat(pinnedCount) * (TabItemView.pinnedWidth + Theme.tabSpacing) + 4
    }

    /// Area for unpinned tabs, after the pinned group.
    private var scrollArea: NSRect {
        var area = tabsArea
        area.origin.x += pinnedWidth
        area.size.width = max(0, area.width - pinnedWidth)
        return area
    }

    private var tabWidth: CGFloat {
        let count = order.count - pinnedCount
        guard count > 0 else { return Theme.tabMaxWidth }
        let fit = (scrollArea.width - Theme.tabSpacing * CGFloat(count - 1)) / CGFloat(count)
        return min(Theme.tabMaxWidth, max(Theme.tabMinWidth, fit.rounded(.down)))
    }

    private var contentWidth: CGFloat {
        let count = order.count - pinnedCount
        return CGFloat(count) * tabWidth + Theme.tabSpacing * CGFloat(max(0, count - 1))
    }

    private var maxScroll: CGFloat { max(0, contentWidth - scrollArea.width) }

    override func layout() {
        super.layout()
        scrollOffset = min(max(0, scrollOffset), maxScroll)
        let area = scrollArea
        let width = tabWidth
        let pinned = pinnedCount
        let selectedIndex = order.firstIndex { $0.isSelected }
        let hoveredIndex = order.firstIndex { $0.isHovered }

        for (index, item) in order.enumerated() where index < pinned {
            let x = tabsArea.minX + CGFloat(index) * (TabItemView.pinnedWidth + Theme.tabSpacing)
            item.frame = NSRect(x: x, y: 0, width: TabItemView.pinnedWidth, height: TabItemView.bodyHeight)
            item.showsSeparator = false
        }
        for (index, item) in order.enumerated() where index >= pinned {
            let position = index - pinned
            var x = area.minX + CGFloat(position) * (width + Theme.tabSpacing) - scrollOffset
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
        clipTabs(to: visible, skipping: pinned)
        closeLeadingGap(after: visible, skipping: pinned)
    }

    /// At the end of the scroll range the tabs align to the trailing edge, which can leave a
    /// gap after the leading guide once a cut tab is hidden. Slide the visible tabs left to the
    /// guide so any slack sits past the last tab instead.
    private func closeLeadingGap(after visible: NSRect, skipping pinned: Int) {
        guard !leadingGuide.isHidden, drag == nil,
              let first = order.dropFirst(pinned).first(where: { !$0.isHidden }) else { return }
        let gap = first.frame.minX - visible.minX
        guard gap > 0.5 else { return }
        for item in order.dropFirst(pinned) where !item.isHidden {
            item.frame.origin.x -= gap
        }
        let lastMaxX = order.last(where: { !$0.isHidden })?.frame.maxX ?? newTabButton.frame.minX
        newTabButton.frame.origin.x = min(lastMaxX + 6, bounds.width - Theme.iconButtonSize - 8)
    }

    private static let guideWidth: CGFloat = 132

    /// Guide words: when tabs overflow, each edge names how many tabs are hidden past it and
    /// the nearest one's title, instead of crushing every tab to an icon. Returns the area
    /// left for tabs once the guides take their edges.
    private func layoutGuideWords(area: NSRect) -> NSRect {
        var visible = area
        let scrolling = order.dropFirst(pinnedCount)
        if scrolling.contains(where: { $0.frame.minX < area.minX - 1 }) {
            visible.origin.x += Self.guideWidth
            visible.size.width -= Self.guideWidth
        }
        if scrolling.contains(where: { $0.frame.maxX > area.maxX + 1 }) {
            visible.size.width -= Self.guideWidth
        }
        let hiddenLeading = scrolling.filter { $0.frame.midX < visible.minX }
        let hiddenTrailing = scrolling.filter { $0.frame.midX > visible.maxX }
        // Each guide hugs the visible tabs; any slack sits at the strip's outer edge.
        let maxWidth = Self.guideWidth - 8
        configureGuide(leadingGuide, hidden: hiddenLeading.reversed(), maxWidth: maxWidth) { width in
            NSRect(x: visible.minX - 4 - width, y: (TabItemView.bodyHeight - 22) / 2, width: width, height: 22)
        }
        configureGuide(trailingGuide, hidden: hiddenTrailing, maxWidth: maxWidth) { width in
            NSRect(x: visible.maxX + 4, y: (TabItemView.bodyHeight - 22) / 2, width: width, height: 22)
        }
        return visible
    }

    private func configureGuide(_ guide: GuideButton, hidden: [TabItemView], maxWidth: CGFloat, frame: (CGFloat) -> NSRect) {
        guard let nearest = hidden.first else { guide.isHidden = true; return }
        guide.isHidden = false
        guide.show(count: hidden.count, nearest: nearest.tab)
        guide.frame = frame(min(maxWidth, guide.intrinsicContentSize.width))
    }

    /// Clicking a guide scrolls the tab it names into view.
    @objc private func revealGuidedTab(_ sender: GuideButton) {
        guard let tab = sender.nearestTab, let index = order.firstIndex(where: { $0.tab === tab }), index >= pinnedCount else { return }
        let step = tabWidth + Theme.tabSpacing
        let position = CGFloat(index - pinnedCount)
        let fits = max(1, ((scrollArea.width - 2 * Self.guideWidth + Theme.tabSpacing) / step).rounded(.down))
        let first = sender.edge == .leading ? position : position - fits + 1
        scrollOffset = first <= 0 ? 0 : min(maxScroll, first * step - Self.guideWidth)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Theme.reduceMotion ? 0 : Theme.panelDuration
            context.allowsImplicitAnimation = true
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }

    /// Tabs cut by an edge are hidden rather than clipped, so the strip never shows a sliver.
    /// The dragged tab is exempt so it can be pulled past the edge to scroll.
    private func clipTabs(to area: NSRect, skipping pinned: Int) {
        for item in order.dropFirst(pinned) where drag?.item !== item {
            item.isHidden = item.frame.minX < area.minX - 1 || item.frame.maxX > area.maxX + 1
        }
    }

    /// Scrolls by whole tabs so the selected tab sits fully inside the guides.
    private func scrollSelectedIntoView() {
        guard let index = order.firstIndex(where: \.isSelected), index >= pinnedCount, maxScroll > 0 else { return }
        let step = tabWidth + Theme.tabSpacing
        let position = CGFloat(index - pinnedCount)
        let fits = max(1, ((scrollArea.width - 2 * Self.guideWidth + Theme.tabSpacing) / step).rounded(.down))
        let firstVisible = scrollOffset <= 0 ? 0 : ((scrollOffset + Self.guideWidth) / step).rounded()
        var first = firstVisible
        if position < firstVisible { first = position }
        if position > firstVisible + fits - 1 { first = position - fits + 1 }
        scrollOffset = first <= 0 ? 0 : min(maxScroll, first * step - Self.guideWidth)
    }

    override func scrollWheel(with event: NSEvent) {
        guard maxScroll > 0 else { return super.scrollWheel(with: event) }
        let delta = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) ? event.scrollingDeltaX : event.scrollingDeltaY
        scrollOffset -= delta * (event.hasPreciseScrollingDeltas ? 1 : 8)
        let finished = event.momentumPhase == .ended || (event.momentumPhase == [] && event.phase == .ended) || !event.hasPreciseScrollingDeltas
        if finished { snapScrollOffset() }
        needsLayout = true
    }

    /// Lands the first visible tab exactly at the leading guide's edge, so overflow never leaves
    /// a tab-sized gap where a clipped tab was hidden.
    private func snapScrollOffset() {
        guard maxScroll > 0, scrollOffset > 0 else { return }
        let step = tabWidth + Theme.tabSpacing
        let index = ((scrollOffset + Self.guideWidth) / step).rounded()
        scrollOffset = min(maxScroll, max(0, index * step - Self.guideWidth))
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
        let mouseX = convert(event.locationInWindow, from: nil).x
        let target: Int
        if item.tab.isPinned {
            let center = mouseX - drag.grabOffset + TabItemView.pinnedWidth / 2 - tabsArea.minX
            target = Int(center / (TabItemView.pinnedWidth + Theme.tabSpacing))
        } else {
            let center = mouseX - drag.grabOffset + tabWidth / 2 + scrollOffset - scrollArea.minX
            target = pinnedCount + Int(center / (tabWidth + Theme.tabSpacing))
        }
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

    func tabItemMenu(_ item: TabItemView) -> NSMenu? { menuForTab?(item.tab) }

    func tabItemDidRequestClose(_ item: TabItemView) {
        drag = nil
        onClose?(item.tab)
    }
}

/// An overflow edge: a drawn chevron, how many tabs are hidden that way (mono), and the
/// nearest one's title. Clicking reveals that tab.
final class GuideButton: NSButton {
    enum Edge { case leading, trailing }
    let edge: Edge
    private(set) weak var nearestTab: Tab?

    init(edge: Edge) {
        self.edge = edge
        super.init(frame: .zero)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = edge == .leading ? .imageLeading : .imageTrailing
        imageHugsTitle = true
        image = NSImage(systemSymbolName: edge == .leading ? "chevron.left" : "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 9, weight: .semibold))
        contentTintColor = Theme.textTertiary
        lineBreakMode = .byTruncatingTail
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var mouseDownCanMoveWindow: Bool { false }

    func show(count: Int, nearest: Tab) {
        nearestTab = nearest
        let title = NSMutableAttributedString()
        if count > 1 {
            title.append(NSAttributedString(string: "\(count) ", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .medium), .foregroundColor: Theme.textTertiary,
            ]))
        }
        title.append(NSAttributedString(string: nearest.displayTitle, attributes: [
            .font: NSFont.systemFont(ofSize: 11), .foregroundColor: Theme.textSecondary,
        ]))
        attributedTitle = title
        let direction = edge == .leading ? "left" : "right"
        toolTip = count == 1 ? "Show \(nearest.displayTitle)" : "\(count) more tabs to the \(direction). Show \(nearest.displayTitle)"
        setAccessibilityLabel(toolTip)
    }
}
