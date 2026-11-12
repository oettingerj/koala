import AppKit
import SwiftUI

/// A native page (Settings, History, Bookmarks) with a search field that ⌘F and opening the page focus.
@MainActor
protocol SearchablePage: NSView {
    func focusSearch()
}

/// A native page whose content ⌘R refreshes (Reviews), instead of reloading a web view.
@MainActor
protocol RefreshablePage: NSView {
    func refresh()
}
