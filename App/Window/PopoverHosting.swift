import SwiftUI

/// Hosts SwiftUI popover content. Publishing `preferredContentSize` lets NSPopover size itself from the
/// SwiftUI layout before showing; otherwise it opens at the view's placeholder size and, as SwiftUI
/// shrinks it, the window keeps its bottom edge and the arrow drifts away from the anchor.
@MainActor
func popoverController<Content: View>(_ view: Content) -> NSViewController {
    let controller = NSHostingController(rootView: view)
    controller.sizingOptions = .preferredContentSize
    return controller
}
