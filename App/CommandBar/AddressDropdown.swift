import AppKit
import BrowserKit
import SwiftUI

/// Suggestions under the address field while it is being edited. Never takes key status, so
/// typing stays in the field; the field forwards ↑/↓/↩ here.
@MainActor
final class AddressDropdown {
    let model: SuggestionModel
    private let panel: NSPanel
    private var heightObservation: ObservationLoop?
    private weak var anchor: NSView?

    var onActivate: ((Suggestion, _ newTab: Bool) -> Void)?

    init(engine: SuggestionEngine) {
        model = SuggestionModel(engine: engine)
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.becomesKeyOnlyIfNeeded = true
        let view = DropdownView(model: model) { [weak self] row in self?.activate(row, newTab: false) }
        panel.contentView = NSHostingView(rootView: view)
        heightObservation = ObservationLoop { [weak self] in self?.layout() }
    }

    var isVisible: Bool { panel.isVisible }

    func update(query: String, anchor: NSView) {
        self.anchor = anchor
        model.update(query: query)
        guard let window = anchor.window else { return }
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            window.addChildWindow(panel, ordered: .above)
        }
        layout()
    }

    func hide() {
        model.reset()
        panel.orderOut(nil)
    }

    /// Returns true when the dropdown consumed the key.
    func moveSelection(by step: Int) -> Bool {
        guard panel.isVisible, !model.rows.isEmpty else { return false }
        model.moveSelection(by: step)
        return true
    }

    func activateSelected(newTab: Bool) -> Bool {
        guard panel.isVisible, let row = model.selected else { return false }
        activate(row, newTab: newTab)
        return true
    }

    private func activate(_ row: Suggestion, newTab: Bool) {
        hide()
        onActivate?(row, newTab)
    }

    private func layout() {
        let count = model.rows.count
        guard let anchor, let window = anchor.window, count > 0 else {
            panel.orderOut(nil)
            return
        }
        let frame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let height = CGFloat(count) * 40 + 12
        panel.setFrame(NSRect(x: frame.minX, y: frame.minY - 4 - height, width: frame.width, height: height), display: true)
        if !panel.isVisible { panel.orderFront(nil) }
    }
}

private struct DropdownView: View {
    @Bindable var model: SuggestionModel
    var onActivate: (Suggestion) -> Void

    var body: some View {
        SuggestionList(model: model, onActivate: onActivate)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .fill(Color(nsColor: Theme.chromeSurface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous)
                    .strokeBorder(Color(nsColor: Theme.hairline), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.panelRadius, style: .continuous))
    }
}
