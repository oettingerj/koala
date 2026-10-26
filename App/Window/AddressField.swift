import AppKit
import BrowserKit

/// The address field. At rest it reads as host in primary text and the rest of the URL in
/// quieter monospace; on focus it becomes the full URL, selected, ready to overwrite.
final class AddressField: NSView {
    private let field = FocusAwareTextField()
    private let border = CALayer()
    private(set) var isEditing = false

    var onSubmit: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private var url: URL?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = Theme.controlRadius
        layer?.cornerCurve = .continuous
        border.cornerRadius = Theme.controlRadius
        border.cornerCurve = .continuous
        border.borderWidth = 0
        layer?.addSublayer(border)

        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Theme.field
        field.textColor = Theme.textPrimary
        field.lineBreakMode = .byTruncatingTail
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.placeholderAttributedString = NSAttributedString(string: "Search or enter address", attributes: [
            .font: Theme.field, .foregroundColor: Theme.textTertiary,
        ])
        field.delegate = self
        field.onFocus = { [weak self] in self?.beginEditing() }
        field.setAccessibilityLabel("Address and search")
        addSubview(field)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var wantsUpdateLayer: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    override func updateLayer() {
        layer?.backgroundColor = resolved(isEditing ? Theme.neutral(0) : Theme.fieldFill)
        border.borderColor = resolved(Theme.accent)
        border.borderWidth = isEditing ? 1.5 : 0
    }

    override func layout() {
        super.layout()
        border.frame = bounds
        let height: CGFloat = 18
        field.frame = NSRect(x: 10, y: (bounds.height - height) / 2, width: bounds.width - 20, height: height)
    }

    func show(_ url: URL?) {
        self.url = url
        guard !isEditing else { return }
        field.attributedStringValue = Self.restingString(for: url)
    }

    func focus(selectingAll: Bool = true) {
        window?.makeFirstResponder(field)
    }

    private func beginEditing() {
        isEditing = true
        field.stringValue = url?.absoluteString ?? ""
        field.textColor = Theme.textPrimary
        needsDisplay = true
        DispatchQueue.main.async { [weak self] in self?.field.currentEditor()?.selectAll(nil) }
    }

    private func endEditing() {
        isEditing = false
        needsDisplay = true
        field.attributedStringValue = Self.restingString(for: url)
    }

    private static func restingString(for url: URL?) -> NSAttributedString {
        guard let url, url.absoluteString != "about:blank", let display = DisplayURL(url) else {
            return NSAttributedString(string: "")
        }
        let string = NSMutableAttributedString(string: display.host, attributes: [
            .font: Theme.field, .foregroundColor: Theme.textPrimary,
        ])
        if !display.remainder.isEmpty {
            string.append(NSAttributedString(string: display.remainder, attributes: [
                .font: Theme.fieldMono, .foregroundColor: Theme.textTertiary, .baselineOffset: 0.5,
            ]))
        }
        return string
    }
}

extension AddressField: NSTextFieldDelegate {
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            let text = field.stringValue
            window?.makeFirstResponder(nil)
            onSubmit?(text)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            window?.makeFirstResponder(nil)
            onCancel?()
            return true
        default:
            return false
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endEditing()
    }
}

/// NSTextField reports focus through the field editor; this surfaces the moment it gains it.
private final class FocusAwareTextField: NSTextField {
    var onFocus: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?() }
        return accepted
    }
}
