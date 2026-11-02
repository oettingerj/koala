import AppKit
import Foundation
import Testing
@testable import BrowserKit

struct MenuShortcutTests {
    @Test func uppercaseLetterAddsShift() {
        let shortcut = MenuShortcut(key: "T", modifiers: .command)
        #expect(shortcut == MenuShortcut(key: "t", modifiers: [.command, .shift]))
        #expect(shortcut.display == "⇧⌘T")
    }

    @Test func ignoresUnrelatedModifiers() {
        let shortcut = MenuShortcut(key: "k", modifiers: [.command, .capsLock, .numericPad])
        #expect(shortcut == MenuShortcut(key: "k", modifiers: .command))
    }

    @Test func displaysModifiersInMenuOrder() {
        #expect(MenuShortcut(key: "\t", modifiers: .control).display == "⌃⇥")
        #expect(MenuShortcut(key: "j", modifiers: [.command, .option]).display == "⌥⌘J")
        #expect(MenuShortcut(key: "]", modifiers: [.command, .shift]).display == "⇧⌘]")
        let right = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))
        #expect(MenuShortcut(key: right, modifiers: [.command, .option]).display == "⌥⌘→")
        let f5 = String(Character(UnicodeScalar(NSF5FunctionKey)!))
        #expect(MenuShortcut(key: f5, modifiers: []).display == "F5")
    }

    @Test func assignableNeedsCommandControlOrFunctionKey() {
        #expect(MenuShortcut(key: "t", modifiers: .command).isAssignable)
        #expect(MenuShortcut(key: "m", modifiers: .control).isAssignable)
        #expect(!MenuShortcut(key: "t", modifiers: []).isAssignable)
        #expect(!MenuShortcut(key: "t", modifiers: [.option, .shift]).isAssignable)
        let f2 = String(Character(UnicodeScalar(NSF2FunctionKey)!))
        #expect(MenuShortcut(key: f2, modifiers: []).isAssignable)
        #expect(!MenuShortcut.none.isAssignable)
    }

    @Test func noneHasNoDisplayOrModifiers() {
        #expect(MenuShortcut.none.isNone)
        #expect(MenuShortcut.none.display == "")
        #expect(MenuShortcut(key: "", modifiers: .command) == .none)
    }

    @Test func roundTripsThroughJSON() throws {
        let saved: [String: MenuShortcut] = [
            "newTab:": MenuShortcut(key: "t", modifiers: [.command, .option]),
            "printPage:": .none,
        ]
        let data = try JSONEncoder().encode(saved)
        #expect(try JSONDecoder().decode([String: MenuShortcut].self, from: data) == saved)
    }
}
