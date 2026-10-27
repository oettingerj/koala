import AppKit
import BrowserKit
import WebKit

/// ⌘F: a slim row above the page. ↩ next, ⇧↩ previous, Esc closes.
final class FindBar: NSView, NSSearchFieldDelegate {
    static let height: CGFloat = 32

    private let field = NSSearchField()
    private let status = NSTextField(labelWithString: "")
    private lazy var previousButton = IconButton(symbol: "chevron.up", label: "Previous Match (⇧⌘G)", pointSize: 11,
                                                 action: #selector(previous), target: self)
    private lazy var nextButton = IconButton(symbol: "chevron.down", label: "Next Match (⌘G)", pointSize: 11,
                                             action: #selector(next), target: self)
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)
    private let hairline = CALayer()

    /// The web view to search: the focused pane.
    var target: () -> WKWebView? = { nil }
    var onVisibilityChange: (() -> Void)?
    private(set) var query = ""

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(hairline)
        field.placeholderString = "Find on page"
        field.font = .systemFont(ofSize: 12)
        field.controlSize = .small
        field.delegate = self
        field.sendsWholeSearchString = false
        field.target = self
        field.action = #selector(fieldChanged)
        status.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        status.textColor = Theme.textTertiary
        doneButton.bezelStyle = .push
        doneButton.controlSize = .small
        doneButton.target = self
        doneButton.action = #selector(close)
        [field, status, previousButton, nextButton, doneButton].forEach(addSubview)
        isHidden = true
        setAccessibilityRole(.group)
        setAccessibilityLabel("Find on page")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = resolved(Theme.chromeSurface)
        hairline.backgroundColor = resolved(Theme.hairline)
    }

    override func layout() {
        super.layout()
        hairline.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 1 / (window?.backingScaleFactor ?? 2))
        let y = (bounds.height - 22) / 2
        field.frame = NSRect(x: 10, y: y, width: min(320, bounds.width * 0.4), height: 22)
        previousButton.frame = NSRect(x: field.frame.maxX + 6, y: (bounds.height - 24) / 2, width: 24, height: 24)
        nextButton.frame = previousButton.frame.offsetBy(dx: 26, dy: 0)
        status.sizeToFit()
        status.frame.origin = NSPoint(x: nextButton.frame.maxX + 10, y: (bounds.height - status.frame.height) / 2)
        doneButton.sizeToFit()
        doneButton.frame.origin = NSPoint(x: bounds.width - doneButton.frame.width - 10, y: (bounds.height - doneButton.frame.height) / 2)
    }

    func show() {
        if isHidden {
            isHidden = false
            onVisibilityChange?()
        }
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    @objc func close() {
        isHidden = true
        status.stringValue = ""
        onVisibilityChange?()
        if let webView = target() { window?.makeFirstResponder(webView) }
    }

    @objc private func fieldChanged() {
        query = field.stringValue
        find(backwards: false)
    }

    @objc private func next() { find(backwards: false) }
    @objc private func previous() { find(backwards: true) }

    func find(backwards: Bool) {
        guard !query.isEmpty, let webView = target() else {
            status.stringValue = ""
            return
        }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.caseSensitive = false
        configuration.wraps = true
        webView.find(query, configuration: configuration) { [weak self] result in
            MainActor.assumeIsolated {
                self?.status.stringValue = result.matchFound ? "" : "Not found"
                self?.status.textColor = result.matchFound ? Theme.textTertiary : Theme.fail
                self?.needsLayout = true
            }
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            find(backwards: NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false)
        case #selector(NSResponder.cancelOperation(_:)):
            close()
        default:
            return false
        }
        return true
    }
}
