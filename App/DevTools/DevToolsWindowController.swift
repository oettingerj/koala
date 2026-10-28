import AppKit
import BrowserKit

/// A normal document-style window, not a nonactivating utility panel: console input needs key focus.
final class DevToolsWindowController: NSWindowController, NSWindowDelegate {
    let model: DevPanelModel
    var onClose: (() -> Void)?
    var onRedock: (() -> Void)?
    private var titleObservation: ObservationLoop?

    init(model: DevPanelModel) {
        self.model = model
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 680),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 480, height: 320)
        window.contentView = DevPanel.host(model: model)
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        window.setFrameAutosaveName("NanoDevToolsWindow")
        titleObservation = ObservationLoop { [weak self] in
            guard let self else { return }
            let url = model.tab?.url
            self.window?.title = "\(model.tab?.displayTitle ?? "Page") · \(model.origin ?? url?.host() ?? "No page") — Developer Tools"
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    func windowWillClose(_ notification: Notification) { titleObservation?.cancel(); onClose?() }
    @objc func toggleDevPanel(_ sender: Any?) { close() }
    @objc func detachDevTools(_ sender: Any?) { onRedock?() }
    @objc func showDevSection(_ sender: NSMenuItem) {
        guard DevPanelModel.Section.allCases.indices.contains(sender.tag) else { return }
        model.section = DevPanelModel.Section.allCases[sender.tag]
    }
}
