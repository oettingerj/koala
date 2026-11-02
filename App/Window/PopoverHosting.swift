import BrowserKit
import SwiftUI

/// A window's popover, kept for the window's life along with one hosting controller per kind of
/// content. Building the popover's window and a fresh SwiftUI graph on every open cost 20–60 ms
/// right as the open animation starts; reusing them leaves only the new root view to update.
@MainActor
final class PopoverPresenter {
    private let popover: NSPopover = {
        let popover = NSPopover()
        popover.behavior = .transient
        return popover
    }()
    private var controllers: [ObjectIdentifier: NSViewController] = [:]

    func show<Content: View>(_ view: Content, from anchor: NSView) {
        popover.close()
        popover.contentViewController = controller(for: view)
        Perf.measure("popover.open") { popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY) }
    }

    func close() { popover.close() }

    /// Publishing `preferredContentSize` lets NSPopover size itself from the SwiftUI layout before
    /// showing; otherwise it opens at the view's placeholder size and, as SwiftUI shrinks it, the
    /// window keeps its bottom edge and the arrow drifts away from the anchor.
    private func controller<Content: View>(for view: Content) -> NSViewController {
        if let controller = controllers[ObjectIdentifier(Content.self)] as? NSHostingController<Content> {
            controller.rootView = view
            return controller
        }
        let controller = NSHostingController(rootView: view)
        controller.sizingOptions = .preferredContentSize
        controllers[ObjectIdentifier(Content.self)] = controller
        return controller
    }
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
