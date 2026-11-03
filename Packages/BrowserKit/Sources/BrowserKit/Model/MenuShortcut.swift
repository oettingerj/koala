import AppKit

/// A menu command's key equivalent: the key as `NSMenuItem.keyEquivalent` takes it, and its modifiers.
/// An empty key means the command has no shortcut.
public struct MenuShortcut: Codable, Hashable, Sendable {
    public let key: String
    /// Raw `NSEvent.ModifierFlags`, limited to ⌃ ⌥ ⇧ ⌘.
    public let modifiers: UInt

    public static let none = MenuShortcut(key: "", modifiers: [])

    private static let relevant: NSEvent.ModifierFlags = [.control, .option, .shift, .command]

    /// Normalizes to the menu's convention: letters are lowercase, and an uppercase letter means ⇧.
    public init(key: String, modifiers: NSEvent.ModifierFlags) {
        var flags = modifiers.intersection(Self.relevant)
        if key.count == 1, key != key.lowercased() {
            flags.insert(.shift)
        }
        self.key = key.lowercased()
        self.modifiers = key.isEmpty ? 0 : flags.rawValue
    }

    public var isNone: Bool { key.isEmpty }

    public var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    /// True for F1–F20, which work as shortcuts without a modifier.
    public var isFunctionKey: Bool {
        guard let scalar = key.unicodeScalars.first, key.unicodeScalars.count == 1 else { return false }
        return (UInt32(NSF1FunctionKey)...UInt32(NSF20FunctionKey)).contains(scalar.value)
    }

    /// A shortcut needs ⌘, ⌃, or ⌥, or is an F-key, so plain typing never triggers a command.
    public var isAssignable: Bool {
        guard !isNone else { return false }
        return isFunctionKey || !modifierFlags.isDisjoint(with: [.command, .control, .option])
    }

    /// The shortcut as menus show it, such as ⇧⌘T. Empty for `none`.
    public var display: String {
        guard !isNone else { return "" }
        let flags = modifierFlags
        var text = ""
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + keyName
    }

    private var keyName: String {
        if isFunctionKey, let scalar = key.unicodeScalars.first {
            return "F\(scalar.value - UInt32(NSF1FunctionKey) + 1)"
        }
        switch key {
        case "\t", "\u{19}": return "⇥"
        case "\r", "\u{3}": return "↩"
        case " ": return "Space"
        case "\u{8}", "\u{7f}": return "⌫"
        case "\u{1b}": return "⎋"
        case String(Character(UnicodeScalar(NSDeleteFunctionKey)!)): return "⌦"
        case String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!)): return "←"
        case String(Character(UnicodeScalar(NSRightArrowFunctionKey)!)): return "→"
        case String(Character(UnicodeScalar(NSUpArrowFunctionKey)!)): return "↑"
        case String(Character(UnicodeScalar(NSDownArrowFunctionKey)!)): return "↓"
        case String(Character(UnicodeScalar(NSHomeFunctionKey)!)): return "↖"
        case String(Character(UnicodeScalar(NSEndFunctionKey)!)): return "↘"
        case String(Character(UnicodeScalar(NSPageUpFunctionKey)!)): return "⇞"
        case String(Character(UnicodeScalar(NSPageDownFunctionKey)!)): return "⇟"
        default: return key.uppercased()
        }
    }
}
