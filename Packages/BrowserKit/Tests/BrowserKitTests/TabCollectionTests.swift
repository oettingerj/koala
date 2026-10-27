import Foundation
import Testing
@testable import BrowserKit

@MainActor
@Suite struct TabCollectionTests {
    private func tab(_ name: String, opener: Tab? = nil) -> Tab {
        Tab(url: URL(string: "https://\(name).com"), title: name, openerID: opener?.id)
    }

    @Test func childrenLandAfterOpenerInOrder() {
        let tabs = TabCollection()
        let a = tab("a"), b = tab("b")
        tabs.insert(a, select: true)
        tabs.insert(b, select: false)
        let c1 = tab("c1", opener: a), c2 = tab("c2", opener: a)
        tabs.insert(c1, select: false)
        tabs.insert(c2, select: false)
        #expect(tabs.tabs.map(\.title) == ["a", "c1", "c2", "b"])
    }

    @Test func closingChildReturnsToOpener() {
        let tabs = TabCollection()
        let a = tab("a"), b = tab("b")
        tabs.insert(a, select: true)
        tabs.insert(b, select: false)
        let child = tab("child", opener: a)
        tabs.insert(child, select: true)
        tabs.remove(child)
        #expect(tabs.selected === a)
    }

    @Test func closingSelectsRightNeighborThenLeft() {
        let tabs = TabCollection()
        let a = tab("a"), b = tab("b"), c = tab("c")
        [a, b, c].forEach { tabs.insert($0, select: false) }
        tabs.select(b)
        tabs.remove(b)
        #expect(tabs.selected === c)
        tabs.remove(c)
        #expect(tabs.selected === a)
        tabs.remove(a)
        #expect(tabs.selected == nil)
    }

    @Test func cyclingWraps() {
        let tabs = TabCollection()
        let a = tab("a"), b = tab("b")
        tabs.insert(a, select: true)
        tabs.insert(b, select: false)
        tabs.selectPrevious()
        #expect(tabs.selected === b)
        tabs.selectNext()
        #expect(tabs.selected === a)
    }

    @Test func movingClearsOpener() {
        let tabs = TabCollection()
        let a = tab("a")
        tabs.insert(a, select: true)
        let child = tab("child", opener: a)
        tabs.insert(child, select: false)
        tabs.move(child, to: 0)
        #expect(tabs.tabs.first === child)
        #expect(child.openerID == nil)
    }

    @Test func pinnedTabsStayGroupedAtFront() {
        let tabs = TabCollection()
        let a = tab("a"), b = tab("b"), c = tab("c")
        [a, b, c].forEach { tabs.insert($0, select: false) }
        tabs.setPinned(c, true)
        tabs.setPinned(b, true)
        #expect(tabs.tabs.map(\.title) == ["c", "b", "a"])
        tabs.move(a, to: 0)
        #expect(tabs.tabs.map(\.title) == ["c", "b", "a"])
        tabs.setPinned(c, false)
        #expect(tabs.tabs.map(\.title) == ["b", "c", "a"])
    }

    @Test func splitAbsorbsPartnerAndUnsplitRestoresIt() {
        let tabs = TabCollection()
        let a = tab("a"), b = tab("b"), c = tab("c")
        [a, b, c].forEach { tabs.insert($0, select: false) }
        tabs.select(a)
        tabs.split(a, with: c)
        #expect(tabs.tabs.map(\.title) == ["a", "b"])
        #expect(tabs.focused === c)
        tabs.focusesSplit = false
        #expect(tabs.focused === a)
        tabs.unsplit(a)
        #expect(tabs.tabs.map(\.title) == ["a", "c", "b"])
        #expect(a.splitTab == nil)
    }

    @Test func splitSurvivesSnapshot() {
        let a = tab("a")
        a.splitTab = Tab(url: URL(string: "https://b.com"), title: "b")
        let restored = Tab(snapshot: a.snapshot)
        #expect(restored.splitTab?.url?.host() == "b.com")
    }
}

@MainActor
@Suite struct TabSleepTests {
    @Test func sleepReleasesWebViewAndWakesWithURL() {
        let tab = Tab(url: URL(string: "about:blank"))
        tab.materialize()
        #expect(tab.webView != nil)
        tab.sleep()
        #expect(tab.webView == nil)
        #expect(tab.url?.absoluteString == "about:blank")
        tab.materialize()
        #expect(tab.webView != nil)
    }
}
