import AppKit
import BrowserKit

/// The address field. At rest it reads as host in primary text and the rest of the URL in
/// quieter monospace; on focus it becomes the full URL, selected, ready to overwrite.
final class AddressField: NSView {
    private let field = FocusAwareTextField()
    private let border = CALayer()
    private(set) var isEditing = false

    /// A warning before the URL when the page isn't secure; nothing for secure pages.
    private let securityIcon = NSImageView()
    var security: PageSecurity = .none { didSet { if security != oldValue { updateSecurity() } } }

    private lazy var starButton = IconButton(symbol: "star", label: "Bookmark This Page", pointSize: 12,
                                             action: #selector(starPressed), target: self)
    var isBookmarked = false { didSet { updateStar() } }
    var canBookmark = false { didSet { starButton.isHidden = !canBookmark || isEditing } }
    var onToggleBookmark: (() -> Void)?

    var onSubmit: ((String) -> Void)?
    /// Typing, ↑/↓, and ↩ are offered to the suggestions dropdown first.
    /// Returns the completion to fill in ahead of the caret, if any.
    var onTextChange: ((String, TextEdit) -> String?)?
    var onMoveSelection: ((Int) -> Bool)?
    var onSubmitSelection: ((_ newTab: Bool) -> Bool)?
    var onEndEditing: (() -> Void)?
    var onCancel: (() -> Void)?

    private var url: URL?
    private let completer = InlineCompleter()

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
        starButton.isHidden = true
        addSubview(starButton)
        updateStar()
        securityIcon.image = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .medium))
        securityIcon.contentTintColor = Theme.fail
        securityIcon.isHidden = true
        addSubview(securityIcon)
    }

    private func updateSecurity() {
        let label: String? = switch security {
        case .insecure: "Not Secure: this page came over plain HTTP"
        case .mixed: "Not Fully Secure: some of this page came over plain HTTP"
        case .exception: "Not Secure: you chose to trust this site’s certificate"
        case .secure, .none: nil
        }
        securityIcon.toolTip = label
        securityIcon.setAccessibilityLabel(label)
        securityIcon.setAccessibilityElement(label != nil)
        needsLayout = true
    }

    @objc private func starPressed() { onToggleBookmark?() }

    private func updateStar() {
        starButton.image = NSImage(systemSymbolName: isBookmarked ? "star.fill" : "star",
                                   accessibilityDescription: isBookmarked ? "Remove Bookmark" : "Bookmark This Page")?
            .withSymbolConfiguration(.init(pointSize: 12, weight: .medium))
        starButton.toolTip = isBookmarked ? "Remove Bookmark (⌘D)" : "Bookmark This Page (⌘D)"
        starButton.contentTintColor = isBookmarked ? Theme.accent : Theme.textTertiary
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
        let starSize: CGFloat = 24
        starButton.frame = NSRect(x: bounds.width - starSize - 2, y: (bounds.height - starSize) / 2, width: starSize, height: starSize)
        let trailing: CGFloat = starButton.isHidden ? 10 : starSize + 4
        securityIcon.isHidden = isEditing || !security.isWarning
        var leading: CGFloat = 10
        if !securityIcon.isHidden {
            securityIcon.frame = NSRect(x: 9, y: (bounds.height - 14) / 2, width: 14, height: 14)
            leading = securityIcon.frame.maxX + 5
        }
        field.frame = NSRect(x: leading, y: (bounds.height - height) / 2, width: bounds.width - leading - trailing, height: height)
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
        starButton.isHidden = true
        needsLayout = true
        field.stringValue = url?.absoluteString ?? ""
        field.textColor = Theme.textPrimary
        needsDisplay = true
        DispatchQueue.main.async { [weak self] in self?.field.currentEditor()?.selectAll(nil) }
        completer.reset()
        // An empty field (a new tab) offers the suggestions' zero state; a page URL offers nothing.
        if field.stringValue.isEmpty { _ = onTextChange?("", .other) }
    }

    private func endEditing() {
        isEditing = false
        starButton.isHidden = !canBookmark
        needsLayout = true
        needsDisplay = true
        field.attributedStringValue = Self.restingString(for: url)
    }

    private static func restingString(for url: URL?) -> NSAttributedString {
        // Native pages read by name at rest; editing shows the koala:// URL.
        if let page = KoalaPage(url: url) {
            return NSAttributedString(string: page.title, attributes: [.font: Theme.field, .foregroundColor: Theme.textPrimary])
        }
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
            let newTab = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
            let handled = onSubmitSelection?(newTab) == true
            window?.makeFirstResponder(nil)
            if !handled { onSubmit?(text) }
            return true
        case #selector(NSResponder.moveUp(_:)):
            return onMoveSelection?(-1) ?? false
        case #selector(NSResponder.moveDown(_:)):
            return onMoveSelection?(1) ?? false
        case #selector(NSResponder.cancelOperation(_:)):
            window?.makeFirstResponder(nil)
            onCancel?()
            return true
        default:
            return false
        }
    }

    #if DEBUG
    func reviewType(_ text: String) {
        window?.makeFirstResponder(field)
        field.stringValue = text
        completer.reset(typed: text)
        completer.show(onTextChange?(text, .typed) ?? nil, in: field)
    }
    #endif

    func controlTextDidChange(_ obj: Notification) {
        let edit = completer.textDidChange(in: field)
        completer.show(onTextChange?(completer.typed, edit) ?? nil, in: field)
    }

    /// Takes the inline completion back out when the suggestions' selection leaves it.
    func clearCompletion() {
        completer.clear(in: field)
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        endEditing()
        onEndEditing?()
    }
}

/// NSTextField reports focus through the field editor; this surfaces the moment it gains it.
private final class FocusAwareTextField: NSTextField {
    var onFocus: (() -> Void)?
    private var focusedByClick = false

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted {
            // A click makes the field first responder before its mouseDown arrives.
            focusedByClick = NSApp.currentEvent?.type == .leftMouseDown
            onFocus?()
        }
        return accepted
    }

    /// The field editor tracks the focusing click until mouse-up and leaves a caret where it
    /// landed, overriding the select-all from focus. A plain click selects all; a drag keeps its range.
    override func mouseDown(with event: NSEvent) {
        let focusingClick = focusedByClick
        focusedByClick = false
        super.mouseDown(with: event)
        guard focusingClick, let editor = currentEditor(), editor.selectedRange.length == 0 else { return }
        editor.selectAll(nil)
    }
}
