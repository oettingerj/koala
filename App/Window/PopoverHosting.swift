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

/// A borderless panel for dropdowns that float over the window but never take key, so the
/// window keeps focus (and its traffic lights) while the dropdown is open.
@MainActor
func dropdownPanel() -> NSPanel {
    let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = true
    panel.isReleasedWhenClosed = false
    panel.animationBehavior = .none
    panel.becomesKeyOnlyIfNeeded = true
    return panel
}

extension View {
    /// The floating panel surface: chrome fill, hairline border, panel radius.
    func dropdownSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
        return background(shape.fill(Color(nsColor: Theme.chromeSurface)))
            .overlay(shape.strokeBorder(Color(nsColor: Theme.hairline), lineWidth: 1))
            .clipShape(shape)
    }
}
