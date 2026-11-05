import Foundation
import Observation

/// The ordered tabs of one window and which one is selected.
@MainActor
@Observable
public final class TabCollection {
    public private(set) var tabs: [Tab] = []
    public private(set) var selectedID: UUID?

    public init() {}

    public var selected: Tab? {
        guard let selectedID else { return nil }
        return tabs.first { $0.id == selectedID }
    }

    /// In a split view, whether the second page has focus.
    public var focusesSplit = false

    /// The page actions and the toolbar apply to: the focused side of a split, else the selected tab.
    public var focused: Tab? {
        guard let selected else { return nil }
        return focusesSplit ? (selected.splitTab ?? selected) : selected
    }

    public var selectedIndex: Int? {
        guard let selectedID else { return nil }
        return tabs.firstIndex { $0.id == selectedID }
    }

    public func index(of tab: Tab) -> Int? {
        tabs.firstIndex { $0.id == tab.id }
    }

    /// Opens `tab`. A tab with an opener lands right after it; the opener may be either page of a split.
    public func insert(_ tab: Tab, select shouldSelect: Bool) {
        var index = tabs.endIndex
        if let openerID = tab.openerID,
           let openerIndex = tabs.firstIndex(where: { $0.id == openerID || $0.splitTab?.id == openerID }) {
            index = max(openerIndex + 1, pinnedCount)
        } else if tab.isPinned {
            index = tabs.firstIndex { !$0.isPinned } ?? tabs.endIndex
        }
        tabs.insert(tab, at: index)
        if shouldSelect || selectedID == nil { select(tab) }
    }

    public func select(_ tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        if selectedID != tab.id { focusesSplit = false }
        selectedID = tab.id
    }

    /// Makes `partner` the second page of `tab`. A partner already in the strip leaves it.
    public func split(_ tab: Tab, with partner: Tab) {
        guard tab.splitTab == nil, partner !== tab else { return }
        if let index = index(of: partner) { tabs.remove(at: index) }
        partner.openerID = nil
        tab.splitTab = partner
        focusesSplit = true
    }

    /// Ends a split. The second page becomes its own tab right after, unless it is discarded.
    @discardableResult
    public func unsplit(_ tab: Tab, keepingPartner: Bool = true) -> Tab? {
        guard let partner = tab.splitTab, let index = index(of: tab) else { return nil }
        tab.splitTab = nil
        focusesSplit = false
        if keepingPartner { tabs.insert(partner, at: index + 1) }
        return partner
    }

    public func select(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        select(tabs[index])
    }

    public func selectNext() { cycleSelection(by: 1) }
    public func selectPrevious() { cycleSelection(by: -1) }

    private func cycleSelection(by step: Int) {
        guard let current = selectedIndex, !tabs.isEmpty else { return }
        select(at: (current + step + tabs.count) % tabs.count)
    }

    /// Removes `tab`. When it was selected, selection returns to its opener if the user was
    /// just reading a child, otherwise moves to the right neighbor (left at the end).
    @discardableResult
    public func remove(_ tab: Tab) -> Int? {
        guard let index = index(of: tab) else { return nil }
        let wasSelected = tab.id == selectedID
        tabs.remove(at: index)

        // Children of a closed tab no longer have a meaningful opener.
        for other in tabs where other.openerID == tab.id { other.openerID = nil }

        guard wasSelected else { return index }
        if tabs.isEmpty {
            selectedID = nil
        } else if let openerID = tab.openerID, tabs.contains(where: { $0.id == openerID }),
                  !(tabs.indices.contains(index) && tabs[index].openerID == openerID) {
            selectedID = openerID
        } else {
            selectedID = tabs[min(index, tabs.count - 1)].id
        }
        return index
    }

    public var pinnedCount: Int { tabs.prefix { $0.isPinned }.count }

    /// Pinned tabs live in a group at the front; pinning moves a tab to the end of that group.
    public func setPinned(_ tab: Tab, _ pinned: Bool) {
        guard tab.isPinned != pinned, let source = index(of: tab) else { return }
        tabs.remove(at: source)
        tab.isPinned = pinned
        tab.openerID = nil
        tabs.insert(tab, at: pinnedCount)
    }

    public func move(_ tab: Tab, to destination: Int) {
        guard let source = index(of: tab) else { return }
        // Pinned and unpinned tabs never interleave.
        let range = tab.isPinned ? 0...max(0, pinnedCount - 1) : pinnedCount...max(pinnedCount, tabs.count - 1)
        let clamped = min(max(destination, range.lowerBound), range.upperBound)
        guard clamped != source else { return }
        tabs.remove(at: source)
        tabs.insert(tab, at: clamped)
        // A tab moved by hand has left its opener's group.
        tab.openerID = nil
    }
}
