import AppKit

/// What the last edit to a field was, as far as inline completion cares.
enum TextEdit {
    /// One character typed at the end: the completion may fill in ahead of it.
    case typed
    /// Text removed from the end, which rejects any completion shown.
    case deleted
    /// A paste, an edit away from the end, or input still composing.
    case other
}

/// Shows the top suggestion's completion inside a text field: the typed text stays, the rest
/// of the address is appended and selected, so typing replaces it, Delete removes it, and
/// → or End accepts it.
@MainActor
final class InlineCompleter {
    /// What the user typed, without any completion.
    private(set) var typed = ""

    /// Classifies the edit that just happened. Call first from `controlTextDidChange`.
    func textDidChange(in field: NSTextField) -> TextEdit {
        let text = field.stringValue
        let editor = field.currentEditor() as? NSTextView
        defer { typed = text }
        if editor?.hasMarkedText() == true { return .other }
        let caretAtEnd = editor.map { $0.selectedRange() == NSRange(location: (text as NSString).length, length: 0) } ?? true
        let old = typed.lowercased(), new = text.lowercased()
        if caretAtEnd, text.count == typed.count + 1, new.hasPrefix(old) { return .typed }
        if text.count <= typed.count, old.hasPrefix(new) { return .deleted }
        return .other
    }

    /// Fills `completion` in after the typed text and selects what was added.
    func show(_ completion: String?, in field: NSTextField) {
        guard let completion, completion.count > typed.count, completion.lowercased().hasPrefix(typed.lowercased()),
              let editor = field.currentEditor() as? NSTextView else { return }
        let text = typed + completion.dropFirst(typed.count)
        let start = (typed as NSString).length
        editor.string = text
        editor.setSelectedRange(NSRange(location: start, length: (text as NSString).length - start))
    }

    /// Takes a shown completion back out, leaving the typed text and the caret after it.
    func clear(in field: NSTextField) {
        guard let editor = field.currentEditor() as? NSTextView, editor.string != typed else { return }
        editor.string = typed
        editor.setSelectedRange(NSRange(location: (typed as NSString).length, length: 0))
    }

    func reset(typed: String = "") {
        self.typed = typed
    }
}
